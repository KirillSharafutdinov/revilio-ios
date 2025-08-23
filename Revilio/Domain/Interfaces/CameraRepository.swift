//
//  CameraRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import AVFoundation
import Combine

/// Protocol for camera operations
protocol CameraRepository {
    /// Set up the camera with specified settings.
    /// - Parameters:
    ///   - preset: Camera resolution preset.
    /// - Returns: A publisher that emits `true` when the setup succeeds, `false` otherwise.
    func setUp(preset: AVCaptureSession.Preset) -> AnyPublisher<Bool, Never>
    
    /// Start camera capture
    func start()
    
    /// Stop camera capture
    func stop()
    
    /// Get preview layer for displaying camera feed
    var previewLayer: AVCaptureVideoPreviewLayer? { get }
    
    /// Get the camera device
    var captureDevice: AVCaptureDevice { get }
    
    /// Set camera zoom level
    /// - Parameter factor: Zoom factor value
    func setZoom(factor: CGFloat)
    
    /// Get current capture session
    var captureSession: AVCaptureSession { get }
    
    /// Capture a single frame on demand as a Combine publisher.
    /// - Returns: A publisher that emits exactly one `CameraFrame` and then completes.
    func singleFrame() -> AnyPublisher<CameraFrame, Never>
    
    /// Async/await variant that returns exactly one captured `CameraFrame`.
    /// The default implementation bridges the Combine publisher. Implementations can
    /// override for a more efficient path.
    func singleFrame() async -> CameraFrame
    
    /// TRUE if the current capture device supports a torch (flashlight)
    var isTorchAvailable: Bool { get }

    /// Turn the torch on or off.
    /// - Parameters:
    ///   - active: Pass `true` to enable the torch, `false` to disable.
    ///   - level: Brightness level between 0.0 and 1.0. Ignored when disabling.
    /// - Returns: `true` if the operation succeeded; otherwise `false`.
    @discardableResult
    func setTorch(active: Bool, level: Float) -> Bool

    // MARK: –  AsyncSequence support
    /// A convenience async sequence of live frames captured from the camera. The default
    /// implementation provided in a protocol extension returns an `AsyncStream` that yields
    /// every frame delivered via `CameraDelegate.didCaptureFrame`. Concrete repositories may
    /// override this for more efficient implementations.
    ///
    /// IMPORTANT: Only **one** consumer should iterate over the returned stream at a time.
    /// Iterating multiple times concurrently will result in undefined behaviour.
    func frames() -> AsyncStream<CameraFrame>
}

extension CameraRepository {
    /// Default bridging implementation: subscribe to the Combine publisher and resume
    /// the continuation with the first emitted frame. The lightweight cancellable is
    /// retained only for the lifetime of the continuation.
    public func singleFrame() async -> CameraFrame {
        await withCheckedContinuation { continuation in
            // Keep the cancellable alive inside the closure scope.
            var cancellable: AnyCancellable? = nil
            cancellable = self.singleFrame()
                .sink { _ in
                    // Completion – no-op; continuation already resumed.
                    cancellable = nil
                } receiveValue: { frame in
                    continuation.resume(returning: frame)
                    cancellable?.cancel()
                    cancellable = nil
                }
        }
    }
} 

extension CameraRepository {
    /// Enables the device torch if the given user-defaults flag is set **and** the hardware supports it.
    /// - Parameters:
    ///   - settingKey: UserDefaults key that stores an `Int` (0/1) representing the flashlight preference.
    ///   - level: Torch brightness (0…1). Defaults to full.
    /// - Returns: `true` when the torch has been successfully enabled so that the caller can later disable it.
    @discardableResult
    func enableTorchIfUserPrefers(settingKey: String, level: Float = 1.0) -> Bool {
        let torchEnabledInSettings = (UserDefaults.standard.object(forKey: settingKey) as? Int ?? 0) == 1
        guard torchEnabledInSettings, isTorchAvailable else { return false }
        return setTorch(active: true, level: level)
    }
}

/// Combine convenience API for `CameraRepository`.
///
/// Usage:
/// ```swift
/// cameraRepository.framePublisher()
///     .sink { frame in /* handle */ }
///     .store(in: &cancellables)
/// ```
///
/// - Warning: Only **one** subscriber should consume the stream at a time – it mirrors the
///   contract of `frames()` which allows a single concurrent iterator.
extension CameraRepository {
    /// Returns a Combine publisher that emits every camera frame produced by the
    /// underlying `AsyncStream` returned from `frames()`.
    ///
    /// The publisher never fails and automatically completes when the underlying
    /// `AsyncStream` terminates.
    public func framePublisher() -> AnyPublisher<CameraFrame, Never> {
        // Bridge the `AsyncStream` produced by `frames()` to Combine manually.  Using a
        // PassthroughSubject keeps compatibility with all deployment targets.
        let subject = PassthroughSubject<CameraFrame, Never>()
        Task {
            for await frame in self.frames() {
                subject.send(frame)
            }
            subject.send(completion: .finished)
        }

        return subject.eraseToAnyPublisher()
    }
}
