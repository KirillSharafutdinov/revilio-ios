//
//  FrameQualityRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Defines an interface for evaluating per-cell sharpness of a video frame.
/// Implementations are expected to be lightweight enough to run in real-time on a background queue.
public protocol FrameQualityRepository {
    /// - Parameter frame: The captured `CameraFrame` to analyse.
    /// – Returns: `FrameSharpnessData` with the computed metrics or `nil` if the evaluation failed.
    func evaluate(frame: CameraFrame) async -> FrameSharpnessData?
} 
