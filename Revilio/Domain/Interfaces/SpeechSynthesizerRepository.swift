//
//  SpeechSynthesizerRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Audio output route options for speech synthesis
enum AudioOutputRoute {
    case receiver      // Quiet output through earpiece/headphones
    case speaker       // Loud output through speakers
}

/// Reading speed options for speech synthesis
enum ReadingSpeed {
    case normal
    case accelerated
    
    var rate: Float {
        switch self {
        case .normal:
            return 0.4
        case .accelerated:
            return 0.6  // 1.5x faster than normal
        }
    }
}

/// Protocol for speech synthesis operations
protocol SpeechSynthesizerRepository: AnyObject {
    // MARK: – Event publishers (Combine)
    /// Emits once for each utterance that finishes naturally or is stopped.
    var didFinish: AnyPublisher<Void, Never> { get }

    // MARK: – Core API
    /// Synthesize speech from text
    /// - Parameter text: The text to speak
    func speak(text: String)
    
    /// Stop current speech synthesis
    func stopSpeaking()
    
    /// Check if speech synthesizer is currently speaking
    var isSpeaking: Bool { get }
    
    /// Get current reading speed
    var readingSpeed: ReadingSpeed { get }
    
    /// Set reading speed
    /// - Parameter speed: The reading speed to set
    func setReadingSpeed(_ speed: ReadingSpeed)
    
    /// Toggle between normal and accelerated reading speed
    func toggleReadingSpeed()
    
    /// Pause current speech synthesis and return the remaining text from the current position if the synthesizer
    /// was speaking. Returns `nil` if nothing was playing. The remaining text should start from the *exact* position
    /// reported by the synthesizer so that resuming will repeat at most one word.
    func pauseSpeaking() -> String?
    
    /// Get current audio output route
    var audioOutputRoute: AudioOutputRoute { get }
    
    /// Set audio output route
    /// - Parameter route: The audio output route to set
    func setAudioOutputRoute(_ route: AudioOutputRoute)
    
    /// Set voice/language for speech synthesizer (runtime language switch support)
    /// - Parameter localeId: Locale identifier, e.g. "en-US", "ru-RU".
    func setVoice(for localeId: String)
    
    /// Activate the suspension barrier and stop everything immediately.
    func suspendOutput()
    
    /// Lift the suspension barrier so that new sessions can produce speech again.
    func resumeOutput()
}
