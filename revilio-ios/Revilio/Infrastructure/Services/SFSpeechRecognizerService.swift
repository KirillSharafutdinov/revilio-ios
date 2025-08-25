//
//  SFSpeechRecognizerService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Speech
import AVFoundation
import Combine

/// Manages continuous speech recognition using Apple's Speech framework, providing real-time
/// transcription with configurable partial results handling. Handles audio session management,
/// recognition state transitions, and provides both Combine publishers and async/await interfaces
/// for transcript streaming. Thread-safe operations with centralized audio resource management.
class SFSpeechRecognizerService: NSObject, SpeechRecognizerRepository {
    private var speechRecognizer: SFSpeechRecognizer?
    private var currentLocale: Locale
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastProcessedText: String = ""
    private var lastMeaningfulText: String = ""  // Store the last meaningful text for fallback
    private var isUsingPartialResults: Bool = false
    private var isFinalizingManually: Bool = false
    private var isRecognitionActive: Bool = false  // Track if recognition is actively running
    private var forcedFinalizationCompleted: Bool = false  // Prevent duplicate processing after force finalization
    
    // Add comprehensive state management
    private var isStartingRecognition: Bool = false
    private var isStoppingRecognition: Bool = false
    private var audioSessionConfigured: Bool = false
    
    // Centralized audio resource manager
    private let resourceManager = AudioResourceManager()
    
    // Serial queue for all speech recognition operations to prevent race conditions
    private let speechQueue = DispatchQueue(label: "com.assistant.speechrecognition", qos: .userInitiated)
    
    // Continuations for async-stream consumers.
    private var speechContinuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    
    private let stateSubject = CurrentValueSubject<SpeechRecognizerState, Never>(.idle)
    
    // Combine bridge – emits every recognition fragment to subscribers
    private let transcriptSubject = PassthroughSubject<String, Never>()
    
    var isAvailable: Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        return speechRecognizer?.isAvailable ?? false && status == .authorized
    }
    
    override init() {
        currentLocale = Locale(identifier: LocalizationManager.shared.currentLanguage.localeId)
        self.speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        super.init()
    }
    
    func startRecognition(usePartialResults: Bool = true) {
        
        // Broadcast state change BEFORE hopping onto serial queue so that subscribers react immediately.
        stateSubject.send(.listening)
        
        // Use serial queue to prevent race conditions
        speechQueue.async { [weak self] in
            self?.performStartRecognition(usePartialResults: usePartialResults)
        }
    }
    
    func stopRecognition() {
        guard isRecognitionActive else {
            return
        }

        // Use serial queue to prevent race conditions
        speechQueue.async { [weak self] in
            self?.performStopRecognition()
        }
    }
    
    func setLanguage(for localeId: String) {
        let locale = Locale(identifier: localeId)
        
        guard SFSpeechRecognizer.supportedLocales().contains(locale) else { return }
        
        guard currentLocale != locale else { return }
        
        stopRecognition()
        
        speechQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.speechRecognizer = SFSpeechRecognizer(locale: locale)
        }
    }
    
    /// Force finalization of current recognition session (for press-and-hold scenarios)
    func forceFinalization() {
        speechQueue.async { [weak self] in
            self?.performForceFinalization()
        }
    }
    
    /// Stream of recognised speech text. Supports multiple simultaneous consumers.
    func recognizedSpeechStream(usePartialResults: Bool = true) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            speechQueue.async { [weak self] in
                guard let self = self else { return }
                self.speechContinuations.append(continuation)

                continuation.onTermination = { @Sendable _ in
                    self.speechQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.speechContinuations.removeAll { existing in
                            return withUnsafePointer(to: existing) { ptr1 in
                                withUnsafePointer(to: continuation) { ptr2 in ptr1 == ptr2 }
                            }
                        }
                        // If no subscribers remain, stop recognition to free resources
                        if self.speechContinuations.isEmpty {
                            self.performStopRecognition()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - SpeechRecognizerRepository Combine bridge
    func transcriptPublisher() -> AnyPublisher<String, Never> {
        transcriptSubject.eraseToAnyPublisher()
    }
        
    func statePublisher() -> AnyPublisher<SpeechRecognizerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Combine state publisher override (prevents auto-start)
    func statePublisher(usePartialResults: Bool = true) -> AnyPublisher<SpeechRecognizerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    private func performStartRecognition(usePartialResults: Bool) {
        // Prevent multiple concurrent recognition starts
        guard !isStartingRecognition && !isStoppingRecognition else {
            return
        }
        
        // If already active, stop first with proper cleanup
        if isRecognitionActive {
            performStopRecognition()
            
            // Wait for cleanup to complete before restarting
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        isStartingRecognition = true
        
        // Reset all state variables
        self.isUsingPartialResults = usePartialResults
        self.isFinalizingManually = false
        self.forcedFinalizationCompleted = false
        lastProcessedText = ""
        lastMeaningfulText = ""
        
        // Ensure complete cleanup first
        cleanupAudioResources()
        
        // Configure audio session with better error handling
        guard resourceManager.configureAudioSession() else {
            isStartingRecognition = false
            let error = NSError(domain: "SFSpeechRecognizerService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio session configuration failed"])
            notifyError(error)
            return
        }
        
        audioSessionConfigured = true
        
        // Create recognition request with enhanced error handling
        guard let recognitionRequest = resourceManager.createRecognitionRequest(usePartialResults: usePartialResults) else {
            isStartingRecognition = false
            return
        }
        
        self.recognitionRequest = recognitionRequest
        
        // Setup audio tap with enhanced error handling and automatic silence detection to force finalisation sooner
        guard resourceManager.safeInstallTap(on: audioEngine, request: recognitionRequest, isActiveCallback: { [weak self] in
            return self?.isRecognitionActive ?? false
        }, silenceHandler: { [weak self] in
            guard let self = self else { return }
            self.recognitionRequest?.endAudio()
        }) else {
            isStartingRecognition = false
            let error = NSError(domain: "SFSpeechRecognizerService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio tap installation failed"])
            notifyError(error)
            return
        }
        
        // Start audio engine with retry logic
        guard resourceManager.safeStart(engine: audioEngine) else {
            isStartingRecognition = false
            return
        }
        
        // Start recognition task
        startRecognitionTask(with: recognitionRequest)
        
        // Mark as active only after everything succeeds
        isRecognitionActive = true
        isStartingRecognition = false
        
    }
    
    private func startRecognitionTask(with request: SFSpeechAudioBufferRecognitionRequest) {
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] (result, error) in
            guard let self = self else { return }
            
            // Use serial queue for callback processing to prevent race conditions
            self.speechQueue.async {
                self.handleRecognitionResult(result: result, error: error)
            }
        }
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        // Ignore callbacks if we've already completed forced finalization or not active
        guard isRecognitionActive && !forcedFinalizationCompleted else {
            return
        }
        
        if let error = error {
            
            // Only handle error if we're not in the middle of forced finalization
            if !isFinalizingManually {
                notifyError(error)
                performStopRecognition()
            }
            return
        }
        
        if let result = result {
            let recognizedText = result.bestTranscription.formattedString.lowercased()
            
            /*
            if result.isFinal {
                print("🟢 [Final Recognition Result]: \(recognizedText)")
            } else {
                print("🟡 [Partial Recognition Result]: \(recognizedText)")
            }
            */
            
            if isUsingPartialResults {
                handlePartialResults(recognizedText: recognizedText, isFinal: result.isFinal)
            } else {
                handleFinalOnlyResults(recognizedText: recognizedText, isFinal: result.isFinal)
            }
        }
    }
    
    private func handlePartialResults(recognizedText: String, isFinal: Bool) {
        // Process partial results and store meaningful text
        if recognizedText != lastProcessedText && !recognizedText.isEmpty {
            lastProcessedText = recognizedText
            
            // Store meaningful text for force finalization
            if recognizedText.count >= 2 {
                lastMeaningfulText = recognizedText
            }
            
            notifyRecognized(recognizedText)
        }
        
        // If we get a final result and we're not manually finalizing, stop recognition
        if isFinal && !isFinalizingManually {
            performStopRecognition()
        }
    }
    
    private func handleFinalOnlyResults(recognizedText: String, isFinal: Bool) {
        if isFinal {
            if !recognizedText.isEmpty {
                lastProcessedText = recognizedText

                // Deliver the transcription **immediately** on the current serial queue so that it reaches
                // all `AsyncStream` consumers *before* we tear them down inside `performStopRecognition()`.
                for cont in speechContinuations {
                    cont.yield(recognizedText)
                }
            } else if !lastMeaningfulText.isEmpty {
                // Use stored meaningful text if final result is empty
                for cont in speechContinuations {
                    cont.yield(self.lastMeaningfulText)
                }
            } else {
                // No meaningful text was detected
                let error = NSError(domain: "SFSpeechRecognizerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
                notifyError(error)
            }
            performStopRecognition()
        } else {
            // Store partial results for potential fallback but don't send to delegate
            if recognizedText.count >= 2 && recognizedText != lastMeaningfulText {
                lastMeaningfulText = recognizedText
            }
        }
    }
    
    private func performStopRecognition() {
        // If another thread has already completed the stop sequence we can bail out early.
        guard isRecognitionActive else {
            return
        }
        
        guard !isStoppingRecognition else {
            return
        }
        
        isStoppingRecognition = true
        
        // Mark recognition as inactive immediately to prevent further processing
        isRecognitionActive = false
        isFinalizingManually = false
        forcedFinalizationCompleted = true
        isStartingRecognition = false  // Reset starting flag
        
        // Use centralized resource manager for safe cleanup
        resourceManager.safeStop(engine: audioEngine, task: recognitionTask, request: recognitionRequest)
        
        // Clear references
        recognitionTask = nil
        recognitionRequest = nil
        
        // After all cleanup is complete we have to finish all AsyncStream continuations so that
        // higher-level helpers such as `SpeechInputHandler` can exit their `for-await` loop and
        // deliver the final result to callers.
        for cont in speechContinuations {
            cont.finish()
        }
        speechContinuations.removeAll()
        
        isStoppingRecognition = false
        
        // Broadcast idle only after full cleanup
        stateSubject.send(.idle)
    }
    
    private func performForceFinalization() {
        guard isRecognitionActive && !forcedFinalizationCompleted else {
            return
        }
        
        // Mark as finalizing to prevent further processing
        isFinalizingManually = true
        forcedFinalizationCompleted = true
        
        // Store the text to deliver before stopping recognition
        let textToDeliver = !lastMeaningfulText.isEmpty ? lastMeaningfulText : lastProcessedText
        
        // print("🟢 [Force Finalization Result]: \(textToDeliver)")
        
        // Yield the text synchronously so it's propagated before we finish continuations.
        for cont in speechContinuations {
            cont.yield(textToDeliver)
        }

        // Now stop recognition (which will finish the continuations).
        performStopRecognition()
    }
    
    /// Request authorization for speech recognition
    /// - Parameter completion: Completion handler with authorization status
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func cleanupAudioResources() {
        
        // Use centralized resource manager for safe cleanup
        resourceManager.safeStop(engine: audioEngine, task: recognitionTask, request: recognitionRequest)
        
        // Clear references
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    // MARK: - Internal helpers (now that delegate API is removed)
    private func notifyRecognized(_ text: String) {
        speechQueue.async { [weak self] in
            guard let self = self else { return }
            for cont in self.speechContinuations {
                cont.yield(text)
            }
            // Also bridge into Combine world.
            self.transcriptSubject.send(text)
        }
    }
    
    private func notifyError(_ error: Error) {
        speechQueue.async { [weak self] in
            guard let self = self else { return }
            // Propagate error to async streams first
            for cont in self.speechContinuations {
                cont.finish(throwing: error)
            }
            self.speechContinuations.removeAll()
            // Broadcast error state
            self.stateSubject.send(.error(error.localizedDescription))
            transcriptSubject.send(completion: .finished)
        }
    }
    
    /// Async/await variant for requesting speech recognition authorisation.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            self.requestAuthorization { granted in
                cont.resume(returning: granted)
            }
        }
    }
    
    /// Combine wrapper around async authorisation request.
    func requestAuthorizationPublisher() -> AnyPublisher<Bool, Never> {
        Deferred {
            Future { [weak self] promise in
                Task {
                    let granted = await self?.requestAuthorization() ?? false
                    promise(.success(granted))
                }
            }
        }.eraseToAnyPublisher()
    }
}
