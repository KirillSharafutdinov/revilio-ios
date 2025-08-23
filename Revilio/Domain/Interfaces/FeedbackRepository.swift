//
//  FeedbackRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Unified abstraction for end-user feedback. Domain layers should depend on this single
/// protocol instead of talking to speech or haptics services directly.
///
/// Implementations decide how to mix tactile and audible output (e.g. `FeedbackPresenter`
/// composes `HapticFeedbackRepository` and `SpeechSynthesizerRepository`).
protocol FeedbackRepository: AnyObject {
    /// Speak (or otherwise present) a textual message to the user.
    func announce(_ message: String)

    /// Play a haptic pattern at the given intensity.
    func play(pattern: HapticPattern, intensity: Float)

    /// Stop any ongoing speech or haptic feedback immediately.
    func stopAll()

    /// Stop all feedback and prevent any further output until `resume()`.
    func stopAndSuspend()

    /// Set the absolute reading speed for subsequent announcements, if supported.
    func setReadingSpeed(_ speed: ReadingSpeed)

    /// Toggle between the default and the fast reading speed.
    func toggleReadingSpeed()

    /// Indicates whether the repository is currently speaking.
    var isSpeaking: Bool { get }

    /// Pause the current speech synthesis and return the remaining text (if any). Returns `nil` if nothing was playing.
    func pauseSpeaking() -> String?

    /// Re-enable speech & haptic feedback after a previous `stopAll()` suspension.
    func resume()

    /// Speak the provided text verbatim. Default implementations can alias this to `announce(_:)`.
    func speak(text: String)

    /// Combine publisher – emits when the underlying speech synthesis finishes.
    var didFinishSpeakingPublisher: AnyPublisher<Void, Never> { get }
}
