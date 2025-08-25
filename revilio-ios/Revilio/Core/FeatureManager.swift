//
//  FeatureManager.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Central registry that keeps weak references to all live `FeatureLifecycle` conformers.
/// It also exposes a Combine publisher so observers (UI, logging, StopController) can react
/// to changes in the running-features set.
public final class FeatureManager {
    /// Singleton instance for app-wide access.  The type remains testable because callers
    /// can swap the shared reference in unit tests if required.
    public static var shared = FeatureManager()

    public var runningFeaturesPublisher: AnyPublisher<[FeatureLifecycle], Never> {
        runningSubject.eraseToAnyPublisher()
    }

    /// Synchronous snapshot of currently running features (thread-safe enough for UI / StopController).
    public var currentRunningFeatures: [FeatureLifecycle] {
        table.allObjects.compactMap { $0 as? FeatureLifecycle }.filter { $0.isRunning }
    }

    private let table = NSHashTable<AnyObject>.weakObjects()

    private let runningSubject = CurrentValueSubject<[FeatureLifecycle], Never>([])

    private init() {}

    // MARK: – Registration helpers
    public func register(_ feature: FeatureLifecycle) {
        table.add(feature)
        refreshRunningList()
    }

    public func unregister(_ feature: FeatureLifecycle) {
        table.remove(feature)
        refreshRunningList()
    }

    /// Called by features when their `isRunning` changes.  O( n ) over the weak table – negligible.
    public func featureStateDidChange() { refreshRunningList() }

    // MARK: – Internal helpers
    private func refreshRunningList() {
        let active = table.allObjects.compactMap { $0 as? FeatureLifecycle }.filter { $0.isRunning }
        runningSubject.send(active)
    }
} 
