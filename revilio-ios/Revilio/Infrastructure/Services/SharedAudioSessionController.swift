//
//  SharedAudioSessionController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import AVFoundation

/// A lightweight, reference-counted controller that coordinates access to the **single**
/// `AVAudioSession` instance shared between speech-recognition (STT) and speech-synthesis (TTS).
///
/// Key goals:
///   • Avoid repeated activate/deactivate thrashing which clips utterances and causes clicks.
///   • Provide a single place where the output route (receiver/speaker) is configured.
///   • Allow multiple subsystems to "begin" and "end" usage without having to know whether
///     other subsystems are still active.
///
/// Usage pattern:
///     SharedAudioSessionController.shared.beginUse(route: .speaker)
///     // … perform TTS or STT …
///     SharedAudioSessionController.shared.endUse(after: 0.05) // optional delay
final class SharedAudioSessionController {
    // MARK: – Public API
    static let shared = SharedAudioSessionController()

    /// Increase the use-count and ensure that the session is configured for the requested route.
    /// - Parameter route: Desired audio output route (.speaker or .receiver).
    /// - Returns: `true` if the session is active and correctly configured, `false` on failure.
    @discardableResult
    func beginUse(route: AudioOutputRoute) -> Bool {
        lock.lock(); defer { lock.unlock() }
        usageCount += 1
        return configureIfNeeded(for: route)
    }

    /// Ensure that the audio route matches the requested value **without** changing the
    /// reference count.  Use this from places that merely toggle between loud/quiet output.
    /// - Returns: `true` if the session matches the requested route (after potential re-config).
    @discardableResult
    func ensureRoute(_ route: AudioOutputRoute) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return configureIfNeeded(for: route)
    }

    /// Decrease the use-count.  When it reaches zero the session is deactivated **after** the
    /// specified delay so that the tail of the last utterance is not clipped.
    /// - Parameter delay: Delay (in seconds) before potential deactivation. Defaults to 0.
    func endUse(after delay: TimeInterval = 0.0) {
        lock.lock(); defer { lock.unlock() }
        guard usageCount > 0 else { return }
        usageCount -= 1
        if usageCount == 0 {
            scheduleDeactivation(after: delay)
        }
    }

    /// Force-deactivate the session **regardless** of the current use count.  Use this when the
    /// user explicitly stops all voice-driven features.
    /// - Returns: `true` on success, `false` on failure.
    @discardableResult
    func forceDeactivate() -> Bool {
        lock.lock(); defer { lock.unlock() }
        usageCount = 0
        return deactivateSession()
    }

    // MARK: – Internals
    private let lock = NSLock()
    private let audioSession = AVAudioSession.sharedInstance()
    private var usageCount: Int = 0
    private var currentRoute: AudioOutputRoute?

    private init() {}

    /// Configure the session when first activated *or* when the desired output route changes.
    /// All calls must be performed while holding `lock`.
    private func configureIfNeeded(for route: AudioOutputRoute) -> Bool {
        // Early-out if already active and on the desired route.
        if let current = currentRoute, current == route {
            return true
        }

        do {
            // Build category options dynamically so that we only apply `.defaultToSpeaker` when the
            // **loud** route is requested.  When the user chooses the quiet earpiece/headphones
            // route we must **not** include this option – otherwise the system will continue to
            // force playback through the speaker regardless of our route override.
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
            if route == .speaker {
                options.insert(.defaultToSpeaker)
            }

            try audioSession.setCategory(.playAndRecord,
                                         mode: .spokenAudio,
                                         options: options)
            // Activate (if not already).
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])

            // Apply route override **after** activation, otherwise the override is ignored.
            try audioSession.overrideOutputAudioPort(route == .speaker ? .speaker : .none)

            currentRoute = route
            return true
        } catch {
            return false
        }
    }

    private func scheduleDeactivation(after delay: TimeInterval) {
        guard delay > 0 else {
            _ = deactivateSession()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            if self.usageCount == 0 { // Nobody grabbed the session in the meantime.
                _ = self.deactivateSession()
            }
        }
    }

    @discardableResult
    private func deactivateSession() -> Bool {
        // Skip deactivation if the session is already inactive to avoid duplicate logs / errors.
        guard currentRoute != nil else { return true }

        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            currentRoute = nil
            return true
        } catch {
            return false
        }
    }
} 
