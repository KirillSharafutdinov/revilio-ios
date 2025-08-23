//
//  FeedbackPresenter.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Feedback type options based on user settings
enum FeedbackType: Int {
    case haptic = 0      // Tactile notifications only
    case sound = 1       // Sound notifications only  
    case both = 2        // Both notifications
}

/// Context for determining which feedback settings to use
enum FeedbackContext {
    case objectSearch
    case textSearch
}

/// Concrete implementation of `FeedbackRepository` that orchestrates
/// both audible (Text-To-Speech) and haptic feedback delivered to the user.
///
/// The presenter automatically respects the user's accessibility
/// preferences stored in `UserDefaults` and avoids overwhelming the user by
/// de-duplicating identical phrases or haptic patterns that occur within a
/// very short interval (`dedupInterval`).
///
/// Additionally, it listens for a global **Stop** event from
/// `StopController` and can suspend all feedback until explicitly resumed
/// by a new session via `resume()`.
final class FeedbackPresenter: FeedbackRepository {
    private let haptics: HapticFeedbackRepository
    private let tts: SpeechSynthesizerRepository
    private let context: FeedbackContext
    
    // Keys for checking user preferences
    private enum DefaultsKey: String {
        case objFeedbackType   = "settings.objFeedbackType"
        case textFeedbackType  = "settings.textFeedbackType"
    }

    // Deduplication caches
    private var lastAnnouncedPhrase: String = ""
    private var lastAnnounceTime: Date = .distantPast
    private var lastHapticPattern: HapticPattern = .none
    private var lastHapticTime: Date = .distantPast
    /// Minimal interval (sec) before allowing the same phrase / pattern again.
    private let dedupInterval: TimeInterval = 0.15

    // Combine bag for internal subscriptions if needed
    private var cancellables = Set<AnyCancellable>()

    // Indicates that feedback has been globally suspended (e.g. after the user pressed Stop).
    // When `true`, all subsequent announce/play requests will be ignored until `resume()`
    // is invoked by a new use-case session.
    private var isSuspended: Bool = false

    init(haptics: HapticFeedbackRepository, tts: SpeechSynthesizerRepository, context: FeedbackContext = .objectSearch) {
        self.haptics = haptics
        self.tts = tts
        self.context = context

        // Automatically suspend feedback when StopController broadcasts a global stop event.
        StopController.shared.didStopAllPublisher
            .sink { [weak self] _ in
                self?.stopAndSuspend()
            }
            .store(in: &cancellables)
    }

    /// Announces the specified `message` using TTS if the current feedback
    /// settings permit sound output. Duplicate phrases triggered within
    /// `dedupInterval` are skipped.
    func announce(_ message: String) {
        guard !isSuspended else { return }
        let feedbackType = getCurrentFeedbackType()
        
        // Deduplicate identical phrase if it was spoken very recently.
        let now = Date()
        
        if message == lastAnnouncedPhrase && now.timeIntervalSince(lastAnnounceTime) < dedupInterval {
            return  // Skip duplicate
        }

        lastAnnouncedPhrase = message
        lastAnnounceTime = now

        // Only announce if sound feedback is enabled
        if feedbackType == .sound || feedbackType == .both {
            tts.speak(text: message)
        }
    }

    /// Plays the given haptic `pattern` with the specified `intensity` when
    /// haptic feedback is enabled. Consecutive identical patterns inside
    /// `dedupInterval` are ignored.
    func play(pattern: HapticPattern, intensity: Float) {
        guard !isSuspended else { return }
        let feedbackType = getCurrentFeedbackType()
        
        // Skip if identical pattern played very recently.
        let now = Date()
        if pattern == lastHapticPattern && now.timeIntervalSince(lastHapticTime) < dedupInterval {
            return
        }

        lastHapticPattern = pattern
        lastHapticTime = now

        // Only play haptic if haptic feedback is enabled
        if feedbackType == .haptic || feedbackType == .both {
            haptics.playPattern(pattern, intensity: intensity)
        }
    }

    /// Immediately stops any ongoing sound or haptic feedback and resets
    /// the internal de-duplication caches.
    func stopAll() {
        tts.stopSpeaking()
        haptics.stop()
        lastAnnouncedPhrase = ""
        lastHapticPattern = .none
    }

    /// Stops all feedback **and** suspends any future output until
    /// `resume()` is invoked.
    func stopAndSuspend() {
        stopAll()
        isSuspended = true

        if let svc = tts as? AVSpeechSynthesizerService {
            svc.suspendOutput()
        }
    }

    /// Re-enables feedback after a previous `stopAndSuspend()` call and
    /// clears internal caches.
    func resume() {
        isSuspended = false
        lastAnnouncedPhrase = ""
        lastHapticPattern = .none

        if let svc = tts as? AVSpeechSynthesizerService {
            svc.resumeOutput()
        }
    }

    /// Sets the TTS reading `speed` (slow, normal, fast).
    func setReadingSpeed(_ speed: ReadingSpeed) {
        tts.setReadingSpeed(speed)
    }

    /// Toggles between the predefined TTS reading speed presets.
    func toggleReadingSpeed() {
        tts.toggleReadingSpeed()
    }
    
    /// `true` while the TTS engine is actively speaking.
    var isSpeaking: Bool {
        return tts.isSpeaking
    }
    
    /// Pauses the current speech and returns the last uttered phrase (if
    /// available) so that it can be resumed later.
    func pauseSpeaking() -> String? {
        return tts.pauseSpeaking()
    }

    /// Speaks the provided plain `text` immediately, bypassing normal
    /// de-duplication.
    func speak(text: String) {
        tts.speak(text: text)
    }

    /// Publisher that emits once the TTS engine completes an utterance.
    var didFinishSpeakingPublisher: AnyPublisher<Void, Never> {
        tts.didFinish
    }

    // MARK: - Private Methods
    
    /// Get current feedback type based on the context
    private func getCurrentFeedbackType() -> FeedbackType {
        let defaults = UserDefaults.standard
        let key = context == .objectSearch ? DefaultsKey.objFeedbackType.rawValue : DefaultsKey.textFeedbackType.rawValue
        let index = defaults.object(forKey: key) as? Int ?? FeedbackType.both.rawValue
        return FeedbackType(rawValue: index) ?? .both
    }
}
