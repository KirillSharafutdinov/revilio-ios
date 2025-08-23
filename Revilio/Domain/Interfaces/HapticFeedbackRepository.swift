//
//  HapticFeedbackRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

public enum HapticPattern {
    case dotPause
    case dashPause
    case dotDashPause
    case dashDotPause
    case continuous
    case none
}

/// Protocol for haptic feedback operations with simple control methods
protocol HapticFeedbackRepository {
    /// Play a haptic pattern with the specified intensity
    /// - Parameters:
    ///   - pattern: The haptic pattern to play
    ///   - intensity: The intensity of the haptic feedback (0.0 to 1.0)
    func playPattern(_ pattern: HapticPattern, intensity: Float)
    
    /// Stop all haptic feedback immediately
    func stop()
}
