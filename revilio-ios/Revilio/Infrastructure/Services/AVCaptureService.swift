//
//  AVCaptureService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import AVFoundation
import UIKit
import Combine

/// Manages the AVFoundation capture pipeline for video input, providing both
/// Combine publishers and async/await interfaces for frame delivery.
/// Handles camera setup, zoom, torch control, and frame streaming.
/// All operations are thread-safe and execute on a dedicated processing queue.
class AVCaptureService: NSObject, CameraRepository {
    // MARK: - Dependencies
    private let logger: Logger
    
    
    // MARK: – Public Properties
    /// The underlying `AVCaptureSession` managing the capture pipeline.
    let captureSession = AVCaptureSession()
    /// The video data output configured for BGRA pixel format.
    let videoOutput = AVCaptureVideoDataOutput()
    /// The currently active capture device.
    var captureDevice: AVCaptureDevice {
        return camera
    }
    /// Indicates whether the current device has a torch (flashlight).
    var isTorchAvailable: Bool {
        return camera.hasTorch
    }
    
    // MARK: – Private Properties
    private let camera: AVCaptureDevice
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private let processingQueue = DispatchQueue(label: "camera-processing-queue")
    // Torch (flashlight) state tracking to avoid redundant hardware calls
    private var torchIsActive: Bool = false
    
    // MARK: – AsyncStream support
    /// Holds the continuation for the live-frame async stream, if `frames()` has been called.
    private var frameStreamContinuation: AsyncStream<CameraFrame>.Continuation?
    
    // MARK: – Initialization
    /// - Parameter logger: Injected logger instance
    init(logger: Logger = OSLogger()) {
        self.logger = logger
        // Get the best available camera
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            self.camera = device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            self.camera = device
        } else if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            self.camera = device
        } else {
            fatalError("No suitable camera device available")
        }
        
        super.init()
    }
    
    // MARK: – Public API
    
    func start() {
        if !captureSession.isRunning {
            processingQueue.async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    func stop() {
        if torchIsActive {
            _ = setTorch(active: false, level: 0)
        }
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func setUp(preset: AVCaptureSession.Preset) -> AnyPublisher<Bool, Never> {
        Deferred {
            Future { [weak self] promise in
                Task {
                    let result = await self?.setUp(preset: preset) ?? false
                    promise(.success(result))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Combine publisher wrapper for the async `singleFrame()`.
    func singleFrame() -> AnyPublisher<CameraFrame, Never> {
        Deferred {
            Future { [weak self] promise in
                Task {
                    if let frame = await self?.singleFrame() {
                        promise(.success(frame))
                    }
                }
            }
        }.eraseToAnyPublisher()
    }

    func setZoom(factor: CGFloat) {
        do {
            try camera.lockForConfiguration()
            
            // Clamp zoom factor to valid range
            let minZoom: CGFloat = 1.0
            let maxZoom: CGFloat = camera.activeFormat.videoMaxZoomFactor
            let clampedFactor = max(minZoom, min(factor, maxZoom))
            
            camera.videoZoomFactor = clampedFactor
            camera.unlockForConfiguration()
        } catch {
            logger.log(.error,
                       "Error setting zoom: \(error.localizedDescription)",
                       category: "CAMERA",
                       file: #file,
                       function: #function,
                       line: #line)
        }
    }
    
    @discardableResult
    func setTorch(active: Bool, level: Float = 1.0) -> Bool {
        // Prevent unnecessary state changes
        if active == torchIsActive { return true }

        var success = false

        let work = {
            guard self.camera.hasTorch else { return }
            do {
                try self.camera.lockForConfiguration()
                if active {
                    let clamped = max(0.0, min(level, 1.0))
                    if self.camera.isTorchModeSupported(.on) {
                        try self.camera.setTorchModeOn(level: clamped)
                    } else {
                        self.camera.torchMode = .on
                    }
                } else {
                    self.camera.torchMode = .off
                }
                self.camera.unlockForConfiguration()
                self.torchIsActive = active
                success = true
            } catch {
                self.logger.log(.error,
                                "Torch configuration error: \(error.localizedDescription)",
                                category: "CAMERA",
                                file: #file,
                                function: #function,
                                line: #line)
            }
        }

        processingQueue.sync(execute: work)

        return success
    }
    
    // MARK: - Combine adapters
    /// Combine publisher for asynchronous camera setup.
    /// Async/await variant of camera setup. Returns `true` on success.
    func setUp(preset: AVCaptureSession.Preset) async -> Bool {
        await withCheckedContinuation { continuation in
            self.setUp(preset: preset) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Async variant that yields exactly one `CameraFrame` from the stream and then returns.
    func singleFrame() async -> CameraFrame {
        if !captureSession.isRunning {
            start()
        }
        var iterator = frames().makeAsyncIterator()
        if let first = await iterator.next() {
            return first
        }
        
        fatalError("Camera stream finished unexpectedly before yielding a frame")
    }
    
    // MARK: - Private methods
    
    private func setUp(preset: AVCaptureSession.Preset, completion: @escaping (Bool) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let success = self.configureCamera(preset: preset)
            
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    private func configureCamera(preset: AVCaptureSession.Preset) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = preset
        
        // Add camera input
        guard let videoInput = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            return false
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            captureSession.commitConfiguration()
            return false
        }
        
        // Configure preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer
        
        // Configure video output
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            captureSession.commitConfiguration()
            return false
        }
        
        // Ensure video connection is set up correctly
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
        
        // Configure camera for continuous auto focus
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            
            camera.unlockForConfiguration()
        } catch {
            logger.log(.error,
                       "Error configuring camera: \(error.localizedDescription)",
                       category: "CAMERA",
                       file: #file,
                       function: #function,
                       line: #line)
            captureSession.commitConfiguration()
            return false
        }
        
        captureSession.commitConfiguration()
        return true
    }
}

// MARK: – AsyncStream API (CameraRepository)

extension AVCaptureService {
    /// Efficient override that yields frames directly from the video-output delegate without going
    /// through the public `delegate` bridge. Only a single consumer is supported.
    func frames() -> AsyncStream<CameraFrame> {
        AsyncStream { continuation in
            // Store continuation so we can yield from delegate callback.
            self.processingQueue.async { [weak self] in
                self?.frameStreamContinuation = continuation
            }

            continuation.onTermination = { @Sendable _ in
                // Clear stored continuation to avoid leaks.
                self.processingQueue.async { [weak self] in
                    self?.frameStreamContinuation = nil
                }
            }
        }
    }
}

// MARK: – Delegate Extensions

extension AVCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let frame = CameraFrame(storage: sampleBuffer)
        frameStreamContinuation?.yield(frame)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // TODO Handle dropped frames if needed
    }
} 

