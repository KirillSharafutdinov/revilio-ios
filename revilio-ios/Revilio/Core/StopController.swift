//
//  StopController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// High-level API for terminating *all* running features (voice tasks, camera pipelines, etc.) with a single call.
/// The controller relies on `FeatureManager` to discover active features and – in later slices – will also
/// silence the shared `FeedbackPresenter` so that no further haptics / TTS are emitted after the stop command.
public final class StopController {
    public enum StopReason { case user, programmatic }

    /// Singleton StopController instance.
    public static let shared = StopController()
    private init() {}

    /// Combine notification for interested observers (UI, analytics).
    private let didStopAllSubject = PassthroughSubject<StopReason, Never>()
    public var didStopAllPublisher: AnyPublisher<StopReason, Never> { didStopAllSubject.eraseToAnyPublisher() }

    /// Invoke to stop every running `FeatureLifecycle`.
    public func stopAll(reason: StopReason = .user) {
        let running = FeatureManager.shared.currentRunningFeatures
        // Call stop() on each running feature.
        running.forEach { $0.stop() }
        // Broadcast stop event – every FeedbackPresenter subscribes and will self-suspend.
        // The dedicated FeedbackRegistry indirection has been removed.
        didStopAllSubject.send(reason)
    }
} 
