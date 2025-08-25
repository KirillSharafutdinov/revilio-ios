//
//  ContinuousFrameProcessor.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// A lightweight component that owns the camera capture loop and publishes frames at a fixed rate.
/// Concrete use-cases hand it a `CameraRepository` and a callback that receives each `CameraFrame`.
/// All callbacks are executed on a dedicated background queue.
final class ContinuousFrameProcessor {

    // MARK: – Private state
    private let cameraRepository: CameraRepository
    private let logger: Logger
    private let processingQueue: DispatchQueue

    private var bag = OperationBag()
    private var isRunning: Bool = false
    
    /// How often to forward frames at most (frames per second).
    private let targetFPS: Double = 16.0

    // MARK: – Init
    /// - Parameters:
    ///   - cameraRepository: Camera access abstraction.
    ///   - logger: Injected logging façade.
    init(cameraRepository: CameraRepository,
         logger: Logger = OSLogger()) {
        self.cameraRepository = cameraRepository
        self.logger = logger
        self.processingQueue = DispatchQueue(label: "continuous-frame-processor", qos: .userInitiated)
    }

    // MARK: – Public control
    /// Starts continuous capture. The `onFrame` closure is executed on the *processing queue*.
    /// Call `stop()` to cancel the loop.
    /// - Parameter onFrame: Callback executed for every captured frame, delivering the
    ///                     platform-agnostic `CameraFrame` wrapper.
    func start(onFrame: @escaping (CameraFrame) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        logger.log(.info, "ContinuousFrameProcessor started", category: "FRAME_PROCESSOR", file: #file, function: #function, line: #line)

        // Subscribe to the camera stream, throttling it to the desired FPS.
        let cancellable = cameraRepository
            .framePublisher()
            // Critically important: without this the frame queue is broken (not cleared), and the oldest frames are fed to the recognizer
            .throttle(for: .seconds(1.0 / targetFPS), scheduler: processingQueue, latest: true)
            .receive(on: processingQueue)
            .sink(receiveCompletion: { [weak self] completion in
                if case let .failure(err) = completion {
                    self?.logger.log(.error, "Camera frame stream failed: \(err.localizedDescription)", category: "FRAME_PROCESSOR", file: #file, function: #function, line: #line)
                }
            }, receiveValue: { frame in
                onFrame(frame)
            })
        bag.add(cancellable)
    }

    /// Cancels any scheduled work and stops the processor.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        bag = OperationBag() // old bag deinit cancels all ops
        logger.log(.info, "ContinuousFrameProcessor stopped", category: "FRAME_PROCESSOR", file: #file, function: #function, line: #line)
    }
} 
