//
//  AVSpeechSynthesizerService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import AVFoundation
import Combine

/// Manages text-to-speech synthesis using AVFoundation's AVSpeechSynthesizer, providing
/// configurable voice output with control over reading speed, audio routing, and voice selection.
/// Handles speech lifecycle events and provides both Combine publishers and async/await interfaces
/// for speech state monitoring. Thread-safe operations with proper audio session management.
class AVSpeechSynthesizerService: NSObject, SpeechSynthesizerRepository {
    // MARK: – Private Properties
    private let didFinishSubject = PassthroughSubject<Void, Never>()
    private let didFailSubject = PassthroughSubject<Error, Never>()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    /// Currently selected voice identifier used for new utterances.  Default to a system-provided voice.
    private var voiceIdentifier: String = AVSpeechSynthesisVoiceIdentifierAlex // Reasonable fallback; will be overridden by `setVoice(for:)`.
    
    // Reading speed management
    private var currentReadingSpeed: ReadingSpeed = .normal
    private let readingSpeedSubject = CurrentValueSubject<ReadingSpeed, Never>(.normal)
    
    // Audio output route management
    /// Persisted key for storing the last selected audio route in `UserDefaults`.
    private static let audioRouteStorageKey = "AudioOutputRoutePreference"
    
    /// Determines the initial audio route. If the user hasn't chosen yet, default to **speaker**
    /// because the UI default also shows the loud option selected. We still read any persisted
    /// preference so we do not overwrite an existing choice.
    private var currentAudioOutputRoute: AudioOutputRoute = {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: AVSpeechSynthesizerService.audioRouteStorageKey) {
            return (stored == "speaker") ? .speaker : .receiver
        } else {
            // No preference saved yet – choose speaker and persist this choice so that subsequent
            // launches are consistent.
            defaults.setValue("speaker", forKey: AVSpeechSynthesizerService.audioRouteStorageKey)
            return .speaker
        }
    }()
    
    // Track if speech was manually stopped to avoid triggering auto-navigation
    private var wasManuallyStopped = false
    
    // Track current utterance to prevent multiple concurrent speeches
    private var currentUtterance: AVSpeechUtterance?
    private var isProcessingSpeech = false
    
    // Speed change management
    private var originalText: String = ""
    private var currentCharacterIndex: Int = 0
    private var isChangingSpeed = false
    
    /// When `true` any incoming `speak(text:)` requests are ignored and any utterances
    /// that do slip through (e.g. were queued just before suspension) are stopped the
    /// moment they begin. This provides a **hard** guarantee that no speech will be
    /// heard after a global Stop action.
    private var isSuspended: Bool = false
    
    /// Holds the text that should be resumed once the current utterance is cancelled during a
    /// reading-speed switch. This lets us wait for the delegate callback instead of guessing a
    /// delay, leading to much more deterministic behaviour.
    private var pendingSpeedChangeText: String?
    
    private let isSpeakingSubject = CurrentValueSubject<Bool, Never>(false)
    
    // MARK: – Public Properties

    /// Publisher that emits every time the reading-speed setting changes.
    var readingSpeedPublisher: AnyPublisher<ReadingSpeed, Never> {
        readingSpeedSubject.eraseToAnyPublisher()
    }
    /// Emits `true` when synthesizer starts speaking and `false` when it finishes or stops.
    var isSpeakingPublisher: AnyPublisher<Bool, Never> {
        isSpeakingSubject.eraseToAnyPublisher()
    }
    
    /// Combine – SpeechSynthesizerRepository conformance
    var didFinish: AnyPublisher<Void, Never> {
        didFinishSubject.eraseToAnyPublisher()
    }
    
    var isSpeaking: Bool {
        return speechSynthesizer.isSpeaking
    }
    
    var readingSpeed: ReadingSpeed {
        return currentReadingSpeed
    }
    
    var audioOutputRoute: AudioOutputRoute {
        return currentAudioOutputRoute
    }
    
    // MARK: – Inizialization

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        
        _ = SharedAudioSessionController.shared.ensureRoute(currentAudioOutputRoute)
        
        setVoice(for: LocalizationManager.shared.currentLanguage.localeId)
    }

    // MARK: - Public API
    
    func speak(text: String) {
        guard !isSuspended else { return }
  
        guard SharedAudioSessionController.shared.beginUse(route: currentAudioOutputRoute) else { return }
        
        if isProcessingSpeech { return }
        
        isProcessingSpeech = true
        
        // Store original text for speed change tracking
        originalText = text
        currentCharacterIndex = 0
        
        if speechSynthesizer.isSpeaking {
            wasManuallyStopped = true  // Mark as manually stopped
            speechSynthesizer.stopSpeaking(at: .immediate)
            
            // Wait a tiny moment for the stop to complete (reduced for snappier navigation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.performSpeak(text: text)
            }
        } else {
            performSpeak(text: text)
        }
    }

    func stopSpeaking() {
        guard speechSynthesizer.isSpeaking else { return }

        wasManuallyStopped = true
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        isProcessingSpeech = false
        currentUtterance = nil
        originalText = ""
        currentCharacterIndex = 0
        isChangingSpeed = false
        // Ensure we release the session if nothing else is using it.
        SharedAudioSessionController.shared.endUse(after: 0.08)
        isSpeakingSubject.send(false)
        // NOTE: Manual interruptions should **not** emit a didFinish event.
        //       This prevents clients like ReadTextUseCase from mistaking a forced stop
        //       for a natural completion and continuing to the next sentence.
        //       Natural completions will still be delivered by the delegate callback
        //       below when `wasManuallyStopped` is false.
        // didFinishSubject.send(())
    }
    
    /// Pauses the current speech immediately and returns the remaining text from the point of pause. The returned
    /// string can be fed back into `speak(text:)` to resume without repeating more than a single word.
    func pauseSpeaking() -> String? {
        guard speechSynthesizer.isSpeaking else { return nil }

        // Capture remaining text before stopping.
        let remainingText = String(originalText.dropFirst(currentCharacterIndex))

        wasManuallyStopped = true
        speechSynthesizer.stopSpeaking(at: .immediate)

        // Leave processing flags cleared so that a future `speak(text:)` call can proceed.
        isProcessingSpeech = false
        currentUtterance = nil
        originalText = ""  // We clear stored text so we don't mis-resume inadvertently.
        currentCharacterIndex = 0
        isChangingSpeed = false

        return remainingText.isEmpty ? nil : remainingText
    }
    
    /// Switch the synthesizer to a voice matching the desired locale, falling back to Alex if unavailable.
    /// - Parameter localeId: BCP-47 locale identifier such as "en-US" or "ru-RU".
    func setVoice(for localeId: String) {
        if let match = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language == localeId }) {
            voiceIdentifier = match.identifier
        } else {
            voiceIdentifier = AVSpeechSynthesisVoiceIdentifierAlex
        }
    }
    
    func setAudioOutputRoute(_ route: AudioOutputRoute) {
        let previousRoute = currentAudioOutputRoute
        guard route != previousRoute else { return } // No change – nothing to do
        
        let valueToStore = (route == .speaker) ? "speaker" : "receiver"
        UserDefaults.standard.setValue(valueToStore, forKey: Self.audioRouteStorageKey)
        
        currentAudioOutputRoute = route
        
        _ = SharedAudioSessionController.shared.ensureRoute(route)
    }
    
    func setReadingSpeed(_ speed: ReadingSpeed) {
        let previousSpeed = currentReadingSpeed
        currentReadingSpeed = speed
        readingSpeedSubject.send(speed)
        
        if speechSynthesizer.isSpeaking && speed != previousSpeed {
            applyInstantSpeedChange()
        }
    }
    
    func toggleReadingSpeed() {
        let newSpeed: ReadingSpeed = (currentReadingSpeed == .normal) ? .accelerated : .normal
        setReadingSpeed(newSpeed)
    }
    
    /// Activate the suspension barrier and stop everything immediately.
    func suspendOutput() {
        guard !isSuspended else { return }
        isSuspended = true
        stopSpeaking()
    }
    
    /// Lift the suspension barrier so that new sessions can produce speech again.
    func resumeOutput() {
        isSuspended = false
    }

    // MARK: - Private Helper Methods
    
    private func performSpeak(text: String) {
        wasManuallyStopped = false
        isChangingSpeed = false
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentReadingSpeed.rate
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        
        currentUtterance = utterance
        speechSynthesizer.speak(utterance)
        isSpeakingSubject.send(true)
    }
    
    private func applyInstantSpeedChange() {
        guard speechSynthesizer.isSpeaking,
              let _ = currentUtterance,
              !originalText.isEmpty else {
            return
        }
                
        isChangingSpeed = true
        wasManuallyStopped = true
        
        let remainingText = String(originalText.dropFirst(currentCharacterIndex))
        pendingSpeedChangeText = remainingText.isEmpty ? nil : remainingText
        
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        if pendingSpeedChangeText == nil {
            isChangingSpeed = false
            wasManuallyStopped = false
        }
    }
    
    private func continueWithNewSpeed(text: String) {
        isChangingSpeed = false
        wasManuallyStopped = false
        
        originalText = text
        currentCharacterIndex = 0
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentReadingSpeed.rate
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        
        currentUtterance = utterance
        speechSynthesizer.speak(utterance)
        isSpeakingSubject.send(true)
    }
    
    /// Error forwarding helper
    private func forward(error: Error) {
        didFailSubject.send(error)
    }
    
    /// Ensures that the active `AVAudioSession` output route matches the user-selected
    /// `currentAudioOutputRoute`. If it does not, the audio session is re-configured.
    private func ensureCorrectAudioRoute() {
        _ = SharedAudioSessionController.shared.ensureRoute(currentAudioOutputRoute)
    }
}

// MARK: - Delegate Extensions

extension AVSpeechSynthesizerService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if isSuspended {
            wasManuallyStopped = true
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance == currentUtterance else { return }
        
        isProcessingSpeech = false
        currentUtterance = nil
        originalText = ""
        currentCharacterIndex = 0
        
        // Only trigger auto-navigation if speech finished naturally, not if manually stopped or changing speed
        if !wasManuallyStopped && !isChangingSpeed {
            didFinishSubject.send(())
        } else if isChangingSpeed, let continuation = pendingSpeedChangeText {
            // Very occasionally the system may deliver a `didFinish` rather than `didCancel` when we
            // call `stopSpeaking(at:)`. Treat it the same way so that our speed-change flow is
            // robust.
            
            pendingSpeedChangeText = nil
            isChangingSpeed = false
            wasManuallyStopped = false
            
            continueWithNewSpeed(text: continuation)
            return
        }
        
        wasManuallyStopped = false
        isChangingSpeed = false
        
        // Release the shared audio session *slightly* after utterance completion to avoid
        // truncating the tail and generating a click/pop.
        SharedAudioSessionController.shared.endUse(after: 0.05)
        isSpeakingSubject.send(false)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        
        // If the cancellation is the result of a speed change, resume immediately with the
        // pending text at the *new* speed.
        if isChangingSpeed, let continuation = pendingSpeedChangeText {

            pendingSpeedChangeText = nil
            isChangingSpeed = false
            wasManuallyStopped = false

            continueWithNewSpeed(text: continuation)
            return
        }

        if !isChangingSpeed {
            isProcessingSpeech = false
            currentUtterance = nil
            originalText = ""
            currentCharacterIndex = 0
        }
        
        // Don't trigger auto-navigation when speech is cancelled
        // This prevents unwanted navigation when user manually stops speech
        wasManuallyStopped = false  // Reset flag only if not changing speed
        // Release the session immediately as cancellation is user-initiated and there is no
        // buffered audio tail to preserve.
        SharedAudioSessionController.shared.endUse(after: 0.0)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Use the *start* of the range so that if speech is paused or the reading speed is
        // toggled **during** this word, we replay it from the beginning rather than skipping
        // its tail. This avoids losing information at the cost of potentially repeating a
        // partially-spoken word, which is preferable for the user experience.
        currentCharacterIndex = characterRange.location
        // Handle word-by-word speaking if needed
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        // TODO we need this later?
    }
}
