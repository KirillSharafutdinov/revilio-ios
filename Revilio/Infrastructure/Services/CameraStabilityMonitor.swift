//
//  CameraStabilityMonitor.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import AVFoundation
import Combine

/// Concrete implementation of `CameraStabilityObserver` that relies on KVO for
/// `AVCaptureDevice` AF/AE convergence and emits a single callback when the
/// scene is deemed stable.
final class CameraStabilityMonitor: NSObject, CameraStabilityObserver {
    // MARK: - Private Properties

    private let device: AVCaptureDevice
    private let requiredStableCount: Int
    private let lensDeltaTolerance: Float
    private let exposureTolerance: Float
    private let logger: Logger

    private var previousLensPosition: Float = 0
    private var stableWindow: [Bool] = [] // Rolling window of most-recent evaluations
    private var isObserving = false
    private var firedCallback = false
    private var bag = OperationBag()
    /// Combine publisher that emits once when the scene becomes stable. Multiple
    /// calls after the first emission are suppressed until `reset()` is invoked.
    private let stabilitySubject = PassthroughSubject<Void, Never>()
    
    
    // MARK: Public Properties
    var onSceneStable: (() -> Void)?
    var stabilityPublisher: AnyPublisher<Void, Never> { stabilitySubject.eraseToAnyPublisher() }

    // MARK: - Inizialization
    /// Creates a new monitor.
    /// - Parameters:
    ///   - device: The capture device whose AF/AE state will be observed.
    ///   - consecutiveStableFrames: How many successive "stable" evaluations are required before we fire the callback.
    ///   - lensDeltaTolerance: Maximum allowed per-frame change in `lensPosition` (0.0…1.0) to still consider the frame stable.
    ///   - exposureTolerance: Maximum allowed absolute `exposureTargetOffset` (EV) to be considered stable.
    ///   - logger: Injected logging façade.
    init(device: AVCaptureDevice,
         consecutiveStableFrames: Int = 3,
         lensDeltaTolerance: Float = 0.005,
         exposureTolerance: Float = 0.25,
         logger: Logger = OSLogger()) {
        self.device = device
        self.requiredStableCount = max(1, consecutiveStableFrames)
        self.lensDeltaTolerance = lensDeltaTolerance
        self.exposureTolerance = exposureTolerance
        self.logger = logger
        super.init()
    }
    
    deinit {
        invalidate()
    }
    
    // MARK: - Public API
    
    func start() {
        guard !isObserving else { return }
        isObserving = true
        previousLensPosition = device.lensPosition
        stableWindow.removeAll(keepingCapacity: true)
        addPublishers()
    }

    /// Resets the monitor state without stopping observation, allowing it to fire again
    func reset() {
        guard isObserving else { return }
        stableWindow.removeAll(keepingCapacity: true)
        firedCallback = false
        previousLensPosition = device.lensPosition
    }
    
    /// Clears the accumulated stability window **without** restarting KVO observation.
    /// This is lighter than `reset()` because it keeps the existing publishers active and
    /// therefore avoids the extra debounce delay after re-subscribing.
    func clearStableWindow() {
        guard isObserving else { return }
        stableWindow.removeAll(keepingCapacity: true)
        firedCallback = false
    }
    
    func invalidate() {
        guard isObserving else { return }
        removePublishers()
        isObserving = false
        stableWindow.removeAll(keepingCapacity: true)
        firedCallback = false
    }

    // MARK: - Private Helpers
    
    private func evaluateCurrentState() {
        // 1. Compute instantaneous stability condition -------------------
        let focusStable = !device.isAdjustingFocus
        // Consider exposure stable if either AE has converged (flag) *or* the EV offset is already within tolerance.
        let evDeltaOk = abs(device.exposureTargetOffset) < exposureTolerance
        let exposureStable = !device.isAdjustingExposure || evDeltaOk
        let lensDeltaOk = abs(device.lensPosition - previousLensPosition) < lensDeltaTolerance

        let stateDescription = String(format: "STABILITY: focus=%@ exposure=%@ adj=%@ EV=%.3f (tol %.3f) lensΔ=%.4f (tol %.4f) -> thisFrameStable=%@",
                                       focusStable ? "OK" : "ADJ",
                                       exposureStable ? "OK" : "-",
                                       device.isAdjustingExposure ? "YES" : "NO",
                                       device.exposureTargetOffset,
                                       exposureTolerance,
                                       abs(device.lensPosition - previousLensPosition),
                                       lensDeltaTolerance,
                                       (focusStable && exposureStable && lensDeltaOk).description)
        #if DEBUG
        logger.log(.debug, stateDescription, category: "CAMERA_STABILITY", file: #file, function: #function, line: #line)
        #endif
        
        previousLensPosition = device.lensPosition
        let stableNow = focusStable && exposureStable && lensDeltaOk

        // 2. Update sliding window ---------------------------------------
        stableWindow.append(stableNow)
        if stableWindow.count > requiredStableCount {
            stableWindow.removeFirst()
        }

        // 3. Check if we accumulated enough consecutive stable frames ----
        if !firedCallback && stableWindow.count == requiredStableCount && stableWindow.allSatisfy({ $0 }) {
            firedCallback = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onSceneStable?()
                self.stabilitySubject.send()
            }
        }
    }
    
    // MARK: - Combine KVO

    private func addPublishers() {
        let focus = device.publisher(for: \AVCaptureDevice.isAdjustingFocus)
        let exposureAdj = device.publisher(for: \AVCaptureDevice.isAdjustingExposure)
        let lensPos = device.publisher(for: \AVCaptureDevice.lensPosition)
        let evOffset = device.publisher(for: \AVCaptureDevice.exposureTargetOffset)

        let cancellable = Publishers.CombineLatest4(focus, exposureAdj, lensPos, evOffset)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue(label: "camera-stability.queue"))
            .sink { [weak self] _, _, _, _ in
                self?.evaluateCurrentState()
            }
        bag.add(cancellable)
    }

    private func removePublishers() {
        bag = OperationBag()
    }
}
