//
//  Revilio
//  StaticImageCameraRepository.swift
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import AVFoundation
import UIKit
import Combine
import CoreMedia
import QuartzCore

class StaticImageCameraService: CameraRepository {
    // MARK: - CameraRepository Protocol Properties
    let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer? = nil
    var captureDevice: AVCaptureDevice {
        guard let device = AVCaptureDevice.default(for: .video) else {
            fatalError("No capture device available in simulator")
        }
        return device
    }
    
    var isTorchAvailable: Bool { false }
    
    // MARK: - Private Properties
    private let images: [UIImage]
    private var currentIndex = 0
    private let frameInterval: TimeInterval
    private var timer: Timer?
    private let frameSubject = PassthroughSubject<CameraFrame, Never>()
    private var frameContinuation: AsyncStream<CameraFrame>.Continuation?
    private let queue = DispatchQueue(label: "StaticCameraService.Queue")
    
    // MARK: - Initialization
    /// - Parameters:
    ///   - images: Статические изображения для циклического показа
    ///   - frameInterval: Интервал смены кадров в секундах (по умолчанию 5 сек)
    init(images: [UIImage], frameInterval: TimeInterval = 5.0) {
        self.images = images
        self.frameInterval = frameInterval
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    }
    
    // MARK: - CameraRepository Protocol Methods
    func setUp(preset: AVCaptureSession.Preset) -> AnyPublisher<Bool, Never> {
        Just(true).eraseToAnyPublisher()
    }
    
    func start() {
        stop()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(
                withTimeInterval: self.frameInterval,
                repeats: true
            ) { [weak self] _ in
                self?.generateFrame()
            }
            self.timer?.fire()
            RunLoop.current.run()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    func setZoom(factor: CGFloat) {
    }
    
    func singleFrame() -> AnyPublisher<CameraFrame, Never> {
        Deferred {
            Future { [weak self] promise in
                let frame = self?.generateFrame() ?? CameraFrame(storage: Data())
                promise(.success(frame))
            }
        }.eraseToAnyPublisher()
    }
    
    func singleFrame() async -> CameraFrame {
        generateFrame()
    }
    
    @discardableResult
    func setTorch(active: Bool, level: Float) -> Bool {
        false
    }
    
    func frames() -> AsyncStream<CameraFrame> {
        AsyncStream { continuation in
            frameContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.frameContinuation = nil
            }
        }
    }
    
    // MARK: - Private Methods
    private func generateFrame() -> CameraFrame {
        let image = images[currentIndex]
        currentIndex = (currentIndex + 1) % images.count
        
        guard let sampleBuffer = image.toSampleBuffer() else {
            return CameraFrame(storage: Data())
        }
        
        let frame = CameraFrame(
            storage: sampleBuffer,
            timestamp: Date().timeIntervalSince1970
        )
        
        frameSubject.send(frame)
        frameContinuation?.yield(frame)
        
        return frame
    }
}

// MARK: - UIImage to CMSampleBuffer Converter
private extension UIImage {
    func toSampleBuffer() -> CMSampleBuffer? {
        guard let pixelBuffer = toPixelBuffer() else { return nil }
        
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
    
    private func toPixelBuffer() -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(
            cgImage!,
            in: CGRect(origin: .zero, size: size)
        )
        return buffer
    }
}
