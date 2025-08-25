//
//  CameraStabilityObserver.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

/// Observes AVFoundation auto-focus (AF) and auto-exposure (AE) convergence
/// and emits a callback when the scene is considered stable.
/// Concrete implementation lives in Infrastructure (CameraStabilityMonitor).
public protocol CameraStabilityObserver: AnyObject {
    /// Closure called exactly once when AF & AE have both settled according to
    /// the configured criteria.
    var onSceneStable: (() -> Void)? { get set }

    /// Starts KVO observation. Calling `start()` while already observing is a no-op.
    func start()

    /// Stops KVO observation and releases all retained objects.
    /// Safe to call multiple times.
    func invalidate()
    
    /// Resets the observer state without stopping observation, allowing it to fire again.
    /// This allows reusing the same observer instance for multiple capture attempts.
    func reset()
}
