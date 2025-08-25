//
//  PredictionService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics

/// Lightweight façade that encapsulates all prediction-related state (detection conviction, position
/// smoothing, ring-buffers, …) that used to live directly in `BaseSearchUseCase`.
final class PredictionService {

    // MARK: – Internal mutable state
    private var session: SearchSession

    
    // MARK: – Public computed accessors
    var detectionConviction: Int {
        get { session.detectionConviction }
        set { session.detectionConviction = newValue }
    }

    var smoothPosition: CGPoint {
        get { session.smoothPosition }
        set { session.smoothPosition = newValue }
    }

    var usePrediction: Bool {
        get { session.usePrediction }
        set { session.usePrediction = newValue }
    }

    var positionHistory: RingBuffer<CGPoint> { session.positionHistory }
    var frameIndexHistory: RingBuffer<Int> { session.frameIndexHistory }

    var currentFrameIndex: Int {
        get { session.currentFrameIndex }
        set { session.currentFrameIndex = newValue }
    }

    // MARK: – Geometry / heuristic constants forwarded from parameters
    var screenCenter: CGPoint { session.screenCenter }
    var centerRadius: Double { session.centerRadius }
    var convictionMax: Int { session.convictionMax }
    var convictionInOnDetect: Int { session.convictionInOnDetect }
    var convictionOutNoDetect: Int { session.convictionOutNoDetect }
    var smoothFactor: Double { session.smoothFactor }

    // MARK: - Initialization
    init(parameters: PredictionParameters = .default) {
        self.session = SearchSession(parameters: parameters)
    }

    // MARK: - Public API
    /// Clears *all* prediction-related runtime data.
    func reset() {
        session.reset()
    }

    /// Linear extrapolation based on the last three stored positions. Returns `nil` when not enough
    /// history is available or calculation fails.
    func predictNextPosition() -> CGPoint? {
        session.predictNextPosition()
    }

    /// Ensures `detectionConviction` remains within the valid range `0…convictionMax`.
    func clampDetectionConviction() {
        detectionConviction = min(max(detectionConviction, 0), convictionMax)
    }

    // MARK: – History mutation helpers
    /// Clears both position and frame-index histories.
    func clearHistory() {
        session.positionHistory.removeAll()
        session.frameIndexHistory.removeAll()
    }

    /// Append a new position sample to the ring buffer.
    func appendPosition(_ point: CGPoint) {
        session.positionHistory.append(point)
    }

    /// Append a new frame index sample.
    func appendFrameIndex(_ index: Int) {
        session.frameIndexHistory.append(index)
    }
} 
