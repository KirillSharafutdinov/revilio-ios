//
//  ObjectDetectionRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Protocol for object detection operations
protocol ObjectDetectionRepository {
    /// Initialize the object detection with a specified model
    /// - Parameter modelName: Name of the ML model to use
    func initialize(modelName: String)
    
    /// Process a new frame for object detection
    /// - Parameter cameraFrame: Pure-Swift `CameraFrame` DTO
    func processFrame(cameraFrame: CameraFrame)
    
    /// Set a confidence threshold for the detection
    /// - Parameter threshold: Confidence threshold value (0.0-1.0)
    func setConfidenceThreshold(_ threshold: Double)
    
    /// Set IoU threshold for the detection
    /// - Parameter threshold: IoU threshold value (0.0-1.0)
    func setIoUThreshold(_ threshold: Double)
    
    // MARK: – AsyncSequence
    /// Structured-concurrency stream of detection results. Implementations must
    /// yield **every** `[ObjectObservation]` batch produced by the Vision pipeline.
    func detectionsStream() -> AsyncStream<[ObjectObservation]>
}

/// Combine wrapper for `ObjectDetectionRepository` AsyncStream API.
extension ObjectDetectionRepository {
    /// Emits every batch of `ObjectObservation` produced by the Vision pipeline.
    /// On iOS 17 the implementation uses the built-in `.publisher` bridging helper;
    /// otherwise a bridging subject is used.
    ///
    /// - Important: The underlying `detectionsStream()` allows **multiple**
    ///   concurrent iterators, therefore the publisher is automatically shared so
    ///   that several subscribers receive the same events without triggering
    ///   duplicate work.
    public func detectionsPublisher() -> AnyPublisher<[ObjectObservation], Never> {
        let subject = PassthroughSubject<[ObjectObservation], Never>()
        Task {
            for await batch in self.detectionsStream() {
                subject.send(batch)
            }
            subject.send(completion: .finished)
        }
        return subject.share().eraseToAnyPublisher()
    }
}
