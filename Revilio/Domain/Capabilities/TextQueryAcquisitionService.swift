//
//  TextQueryAcquisitionService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Determines whether the caller wants live partial updates (`streaming`) or the classic
/// final-only behaviour (`disabled`). This is a *constructor* option – switching it at run-time
/// is not supported because the underlying recogniser has to be configured *before* start.
public enum PartialReportingMode {
    /// Receive every partial hypothesis as it arrives – recommended for text-search flows.
    case streaming
    /// Suppress partial results; only the recogniser's final transcription will be delivered.
    case disabled
}

/// Streaming implementation that buffers *partial* speech recognition results and returns the latest
/// non-empty transcript when the recogniser finishes or is force-finalised. Designed for text-search
/// flows where we want the *full* phrase even if the user keeps talking until timeout.
final class TextQueryAcquisitionService: ItemQueryAcquiring {
    // MARK: - Dependencies
    /// Combine-based speech recogniser dependency
    private let speechRecognizer: SpeechRecognizerRepository
    
    // MARK: - Configuration
    /// The selected partial reporting mode (streaming vs disabled)
    private let mode: PartialReportingMode
    /// Internal timeout after the last partial recognised. If the user stops speaking and the
    /// recogniser does *not* deliver a `isFinal` in this window, we force-finalise.
    private let trailingSilenceInterval: TimeInterval
    
    // MARK: - State Management
    /// Keeps the newest non-empty partial so that we can still return something meaningful on timeout.
    private var latestTranscript: String = ""
    /// Indicates whether we've received at least one non-empty partial result – used to
    /// decide when to start the trailing-silence supervision.
    private var hasReceivedFirstPartial = false

    private var cancellable: AnyCancellable?
    /// Timer used to detect trailing silence (no partial updates) *after* speech has started.
    private var silenceTimer: Timer?
    /// List of continuations attached via `partialTranscriptStream()` so multiple
    /// observers (e.g. UI) can receive live updates.
    private var partialContinuations: [AsyncStream<String>.Continuation] = []
    
    // MARK: - Concurrency
    /// Serial queue to protect cross-thread access to the above state.
    private let syncQueue = DispatchQueue(label: "streaming.speech.query.sync")

    // MARK: - Initialization

    init(speechRecognizer: SpeechRecognizerRepository,
         mode: PartialReportingMode = .streaming,
         trailingSilenceInterval: TimeInterval = 1.2) {
        self.speechRecognizer = speechRecognizer
        self.mode = mode
        self.trailingSilenceInterval = trailingSilenceInterval
    }

    // MARK: - Public API - ItemQueryAcquiring
    func acquireQuery(timeout: TimeInterval) async throws -> String {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var finished = false

            func finish(returning text: String) {
                guard !finished else { return }
                finished = true
                continuation.resume(returning: text)
            }

            func finish(throwing error: Error) {
                guard !finished else { return }
                finished = true
                continuation.resume(throwing: error)
            }

            syncQueue.async { self.latestTranscript = "" }
            
            // Subscribe to the Combine publisher emitting recognition fragments.
            self.cancellable = self.speechRecognizer.transcriptPublisher()
                .sink { [weak self] text in
                    guard let self else { return }
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
                    
                    self.syncQueue.async {
                        self.latestTranscript = text

                        if self.mode == .streaming {
                            if !self.hasReceivedFirstPartial {
                                self.hasReceivedFirstPartial = true
                                // Start trailing-silence supervision *now* (after first words).
                                self.startSilenceTimer { [weak self] in
                                    self?.speechRecognizer.forceFinalization()
                                    // After a small grace period, finish with the latest transcript.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        self?.syncQueue.async {
                                            finish(returning: self?.latestTranscript ?? text)
                                        }
                                    }
                                }
                            } else {
                                // Restart timer on every subsequent partial so that we wait for
                                // silence *after* the user's last spoken words.
                                self.resetSilenceTimer(force: false) { [weak self] in
                                    self?.speechRecognizer.forceFinalization()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        self?.syncQueue.async {
                                            finish(returning: self?.latestTranscript ?? text)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Stream partials to AsyncStream subscribers when enabled.
                        if self.mode == .streaming {
                            self.partialContinuations.forEach { $0.yield(text) }
                        }
                    }
                }
            
            // Start recognition after setting up the subscriber.
            speechRecognizer.startRecognition(usePartialResults: (self.mode == .streaming))

            // Global timeout supervision – if no finalisation occurs within the given timeout
            // we force the recogniser to finish and return whatever text we've heard so far.
            if timeout > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self, !finished else { return }
                    self.speechRecognizer.forceFinalization()
                    self.syncQueue.async {
                        finish(returning: self.latestTranscript)
                    }
                }
            }
        }
    }

    func cancel() {
        silenceTimer?.invalidate()
        cancellable?.cancel()
        speechRecognizer.stopRecognition()
        finishContinuations()
    }

    func forceFinalization() {
        speechRecognizer.forceFinalization()
    }
    
    // MARK: – Public streaming API
    /// Returns an `AsyncStream` that emits every partial transcript recognised so far. Multiple
    /// callers may subscribe concurrently; the stream terminates when recognition stops or the
    /// service is cancelled.
    func partialTranscriptStream() -> AsyncStream<String> {
        // If partials are disabled return an already-finished stream to avoid waiting forever.
        guard mode == .streaming else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            // Register continuation under lock.
            syncQueue.async { [weak self] in
                self?.partialContinuations.append(continuation)
            }

            continuation.onTermination = { @Sendable _ in
                self.syncQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.partialContinuations.removeAll { existing in
                        return withUnsafePointer(to: existing) { p1 in
                            withUnsafePointer(to: continuation) { p2 in p1 == p2 }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startSilenceTimer(finalisationHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.trailingSilenceInterval, repeats: false) { _ in
                finalisationHandler()
            }
        }
    }

    private func resetSilenceTimer(force: Bool, finalisationHandler: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            if force {
                self.silenceTimer?.invalidate()
                self.silenceTimer = nil
            }
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.trailingSilenceInterval, repeats: false) { _ in
                finalisationHandler()
            }
        }
    }

    private func finishContinuations() {
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.partialContinuations.forEach { $0.finish() }
            self.partialContinuations.removeAll()
        }
    }
} 


