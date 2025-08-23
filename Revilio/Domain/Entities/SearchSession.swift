//
//  SearchSession.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics

/// Configuration parameters that influence object position smoothing, conviction counters and center corridor logic.
public struct PredictionParameters {
    // MARK: - Public immutable properties
    public let center: CGPoint
    public let centerRadius: Double
    public let convictionMax: Int
    public let convictionInOnDetect: Int
    public let convictionOutNoDetect: Int
    public let smoothFactor: Double

    // MARK: - Default Configuration
    public static let `default` = PredictionParameters(
        center: CGPoint(x: 0.5, y: 0.5),
        centerRadius: 0.1,
        convictionMax: 10,
        convictionInOnDetect: 4,
        convictionOutNoDetect: 1,
        smoothFactor: 0.1
    )
}

/// Captures the mutable state of a running search (object or text).
/// Holds detection conviction, smoothed coordinates and prediction ring buffers.
public final class SearchSession {
    // MARK: - Configuration

    public let parameters: PredictionParameters

    // MARK: – State Management
    public var detectionConviction: Int = 0
    public var smoothPosition: CGPoint = CGPoint(x: -1.0, y: -1.0)
    public var currentFrameIndex: Int = 0
    public var usePrediction: Bool = true
    /// Ring-buffers (constant small memory footprint)
    public var positionHistory: RingBuffer<CGPoint>
    public var frameIndexHistory: RingBuffer<Int>

    // MARK: – Initialization

    public init(parameters: PredictionParameters = .default) {
        self.parameters = parameters
        self.positionHistory = RingBuffer<CGPoint>(capacity: 3)
        self.frameIndexHistory = RingBuffer<Int>(capacity: 3)
    }

    // MARK: – Computed Properties
    public var screenCenter: CGPoint { parameters.center }
    public var centerRadius: Double { parameters.centerRadius }
    public var convictionMax: Int { parameters.convictionMax }
    public var convictionInOnDetect: Int { parameters.convictionInOnDetect }
    public var convictionOutNoDetect: Int { parameters.convictionOutNoDetect }
    public var smoothFactor: Double { parameters.smoothFactor }

    // MARK: – Public API
    public func reset() {
        detectionConviction = 0
        smoothPosition = CGPoint(x: -1.0, y: -1.0)
        positionHistory.removeAll()
        frameIndexHistory.removeAll()
        currentFrameIndex = 0
    }

    /// Performs linear-regression extrapolation to guess the next position.
    public func predictNextPosition() -> CGPoint? {
        guard positionHistory.count >= 3 else { return nil }

        let xValues = frameIndexHistory.map(Double.init)
        let yValuesX = positionHistory.map { Double($0.x) }
        let yValuesY = positionHistory.map { Double($0.y) }
        let nextFrameIndex = Double(currentFrameIndex + 1)

        guard let predictedX = linearExtrapolation(xValues: xValues, yValues: yValuesX, forX: nextFrameIndex),
              let predictedY = linearExtrapolation(xValues: xValues, yValues: yValuesY, forX: nextFrameIndex) else {
            return nil
        }
        return CGPoint(x: clamp(predictedX), y: clamp(predictedY))
    }
    
    // MARK: – Private Helpers

    private func linearExtrapolation(xValues: [Double], yValues: [Double], forX targetX: Double) -> Double? {
        guard xValues.count == yValues.count, xValues.count >= 2 else { return nil }
        let sumX = xValues.reduce(0, +)
        let sumY = yValues.reduce(0, +)
        let sumXY = zip(xValues, yValues).map { $0 * $1 }.reduce(0, +)
        let sumX2 = xValues.map { $0 * $0 }.reduce(0, +)
        let n = Double(xValues.count)
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return nil }
        let b = (n * sumXY - sumX * sumY) / denom
        let a = (sumY - b * sumX) / n
        return a + b * targetX
    }

    private func clamp(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }
} 
