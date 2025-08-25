//
//  CoreHapticsFeedbackManager.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreHaptics
import UIKit
import Combine
import os

// MARK: - CoreHapticsFeedbackManager
/// Manages haptic feedback using Core Haptics framework, providing configurable vibration patterns
/// with intensity control and fallback support for older devices. Handles pattern sequencing,
/// engine lifecycle, and provides Combine publishers for haptic state monitoring.
class CoreHapticsFeedbackManager: HapticFeedbackRepository {
    
    // MARK: - Private Properties
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var cancellables = Set<AnyCancellable>()
    private let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "HAPTIC_FEEDBACK")

    /// Pattern management
    private var currentPattern: HapticPattern = .none
    private var currentIntensity: Float = 0.0
    private var pendingPattern: HapticPattern?
    private var pendingIntensity: Float = 0.0
    
    /// State tracking
    private var isPlayingPattern = false
    private var shouldStop = false
    
    /// Timer for pattern duration tracking
    private var patternTimer: Timer?
    
    /// Thread safety
    private let queue = DispatchQueue(label: "haptic.feedback.queue", qos: .userInteractive)
    
    /// Pattern timing configuration
    private struct PatternTiming {
        let dotDuration: TimeInterval = 0.12
        let dashDuration: TimeInterval = 0.5
        let pauseAfterDot: TimeInterval = 0.25
        let pauseAfterDash: TimeInterval = 0.35
        let continuousDuration: TimeInterval = 0.25
        let patternGap: TimeInterval = 0.5
    }
    
    private let timing = PatternTiming()
    
    /// Combine state publisher
    private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)
    
    // MARK: - Public Properties
    
    /// Combine publisher that emits `true` while a haptic pattern is playing and `false` when idle.
    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init() {
        setupHapticEngine()
        setupLifecycleObservers()
    }
    
    deinit {
        queue.sync {
            patternTimer?.invalidate()
            stopContinuousPlayer()
            engine?.stop()
            
            // Cancel Combine pipelines
            cancellables.forEach { $0.cancel() }
        }
    }
    
    // MARK: - Public Methods - HapticFeedbackRepository Implementation
    
    func playPattern(_ pattern: HapticPattern, intensity: Float) {
        guard pattern != .none else {
            stop()
            return
        }
        
        let clampedIntensity = max(0.0, min(1.0, intensity))
        
        queue.async { [weak self] in
            self?.handlePlayRequest(pattern: pattern, intensity: clampedIntensity)
        }
    }
    
    func stop() {
        queue.async { [weak self] in
            self?.handleStopRequest()
        }
    }
    
    // MARK: - Engine Setup
    
    private func setupHapticEngine() {
        if !CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            return
        }
        
        do {
            engine = try CHHapticEngine()
            
            engine?.stoppedHandler = { [weak self] reason in
                self?.engineStoppedHandler(reason: reason)
            }
            
            engine?.resetHandler = { [weak self] in
                self?.engineResetHandler()
            }
            
            try engine?.start()
            
        } catch {
        }
    }
    
    private func engineStoppedHandler(reason: CHHapticEngine.StoppedReason) {
        if reason != .audioSessionInterrupt && reason != .applicationSuspended {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupHapticEngine()
            }
        }
    }
    
    private func engineResetHandler() {
        do {
            try engine?.start()
        } catch {
        }
    }
    
    private func restartEngineIfNeeded() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        if engine == nil {
            setupHapticEngine()
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                if try self.engine?.start() == nil {
                    self.setupHapticEngine()
                }
            } catch {
                self.setupHapticEngine() // Full recreate on failure
            }
        }
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.queue.async {
                    self?.restartEngineIfNeeded()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.queue.async {
                    self?.engine?.stop()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Private Request Handling Managment
    
    private func handlePlayRequest(pattern: HapticPattern, intensity: Float) {
        shouldStop = false
        
        if isPlayingPattern {
            // Store the new pattern request to play after current one completes
            pendingPattern = pattern
            pendingIntensity = intensity
        } else {
            // Play immediately
            startPatternPlayback(pattern: pattern, intensity: intensity)
        }
    }
    
    private func handleStopRequest() {
        // Prevent duplicate stop handling (e.g. Stop button + timer completion)
        guard !shouldStop else { return } // Already stopped, no-op

        shouldStop = true
        pendingPattern = nil
        pendingIntensity = 0.0
        
        // Stop current pattern immediately
        patternTimer?.invalidate()
        patternTimer = nil
        stopContinuousPlayer()
        
        currentPattern = .none
        currentIntensity = 0.0
        isPlayingPattern = false
        isActiveSubject.send(false)
        
    }
    
    private func stopContinuousPlayer() {
        if let player = continuousPlayer {
            do {
                try player.stop(atTime: CHHapticTimeImmediate)
                continuousPlayer = nil
            } catch {
            }
        }
    }
    
    // MARK: - Private Pattern Management
    
    private func startPatternPlayback(pattern: HapticPattern, intensity: Float) {
        guard !shouldStop else { return }
        
        currentPattern = pattern
        currentIntensity = intensity
        
        isPlayingPattern = true
        isActiveSubject.send(true)
        
        guard let engine = engine else {
            fallbackToUIKit(pattern: pattern, intensity: intensity)
            onPatternComplete()
            return
        }
        
        do {
            let hapticPattern = try createHapticPattern(for: pattern, intensity: intensity)
            let player = try engine.makePlayer(with: hapticPattern)
            
            // Calculate total pattern duration
            let duration = calculatePatternDuration(pattern, intensity: intensity)
            
            // Start the pattern
            try player.start(atTime: CHHapticTimeImmediate)
            
            // Set timer for pattern completion
            DispatchQueue.main.async { [weak self] in
                self?.patternTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                    self?.queue.async {
                        self?.onPatternComplete()
                    }
                }
            }
        
        } catch {
            fallbackToUIKit(pattern: pattern, intensity: intensity)
            onPatternComplete()
        }
        
    }
    
    private func onPatternComplete() {
        guard !shouldStop else { return }
        
        isPlayingPattern = false
        isActiveSubject.send(false)
        
        // Check if there's a pending pattern to play
        if let nextPattern = pendingPattern {
            let nextIntensity = pendingIntensity
            pendingPattern = nil
            pendingIntensity = 0.0
            
            startPatternPlayback(pattern: nextPattern, intensity: nextIntensity)
        } else {
            handleStopRequest()
        }
    }
    
    // MARK: - Pattern Duration Calculation
    
    /// Speed Factor Calculation
    private func speedFactor(for intensity: Float) -> Double {
        return 1.0 + Constants.Haptics.speedFactorSlope * Double(intensity)
    }

    private func calculatePatternDuration(_ pattern: HapticPattern, intensity: Float) -> TimeInterval {
        let speedFactor = speedFactor(for: intensity)
        let baseDuration: TimeInterval
        
        switch pattern {
        case .dotPause:
            baseDuration = timing.dotDuration + timing.pauseAfterDot*(8 - min(8, speedFactor))/6 + timing.patternGap*(8 - min(8, speedFactor))/6 // x = 1 for y = 1, x = 0.1 for y = 5
        case .dashPause:
            baseDuration = timing.dashDuration/speedFactor + timing.pauseAfterDash/speedFactor + timing.patternGap/speedFactor
        case .dotDashPause:
            baseDuration = timing.dotDuration + timing.pauseAfterDot/speedFactor + timing.dashDuration/speedFactor + timing.pauseAfterDash/speedFactor + timing.patternGap/(speedFactor/5)
        case .dashDotPause:
            baseDuration = timing.dashDuration/speedFactor + timing.pauseAfterDash/speedFactor + timing.dotDuration + timing.pauseAfterDot/speedFactor + timing.patternGap/(speedFactor/5)
        case .continuous, .none:
            baseDuration = timing.continuousDuration
        }
        
        return baseDuration
    }
    
    // MARK: - Core Haptics Pattern Creation
    
    private func createHapticPattern(for patternType: HapticPattern, intensity: Float) throws -> CHHapticPattern {
        let speedFactor = speedFactor(for: intensity)
        
        // Adjust all timings by speed factor
        let dotDuration = timing.dotDuration / speedFactor
        let dashDuration = timing.dashDuration / speedFactor
        let pauseAfterDot = timing.pauseAfterDot / speedFactor
        let pauseAfterDash = timing.pauseAfterDash / speedFactor
        let continuousDuration = timing.continuousDuration
        
        var events: [CHHapticEvent] = []
        var time: TimeInterval = 0
        
        let clampedIntensity = max(0.2, min(1.0, intensity))
        let sharpness: Float = patternType == .continuous ? 0.7 : 0.9
        
        switch patternType {
        case .dotPause:
            events.append(createTransientEvent(intensity: clampedIntensity, sharpness: sharpness, time: time))
            
        case .dashPause:
            events.append(createContinuousEvent(intensity: clampedIntensity * 0.85, sharpness: 0.6, time: time, duration: dashDuration))
            
        case .dotDashPause:
            // Dot
            events.append(createTransientEvent(intensity: 0.7, sharpness: sharpness, time: time))
            time += dotDuration + pauseAfterDot * 3
            
            // Dash
            events.append(createContinuousEvent(intensity: clampedIntensity * 0.85, sharpness: 0.6, time: time, duration: dashDuration))
            
        case .dashDotPause:
            // Dash
            events.append(createContinuousEvent(intensity: clampedIntensity * 0.85, sharpness: 0.6, time: time, duration: dashDuration))
            time += dashDuration + pauseAfterDash * 1.5
            
            // Dot
            events.append(createTransientEvent(intensity: 0.7, sharpness: sharpness, time: time))
            
        case .continuous:
            events.append(createContinuousEvent(intensity: clampedIntensity, sharpness: sharpness, time: time, duration: continuousDuration))
            
        case .none:
            break
        }
        
        return try CHHapticPattern(events: events, parameters: [])
    }
    
    private func createTransientEvent(intensity: Float, sharpness: Float, time: TimeInterval) -> CHHapticEvent {
        return CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }
    
    private func createContinuousEvent(intensity: Float, sharpness: Float, time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        return CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    // MARK: - Fallback Support
    
    private func fallbackToUIKit(pattern: HapticPattern, intensity: Float) {
        guard pattern != .none else { return }
        
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        if intensity < 0.3 {
            feedbackStyle = .light
        } else if intensity < 0.7 {
            feedbackStyle = .medium
        } else {
            feedbackStyle = .heavy
        }
        
        UIImpactFeedbackGenerator(style: feedbackStyle).impactOccurred(intensity: CGFloat(intensity))
    }
}
