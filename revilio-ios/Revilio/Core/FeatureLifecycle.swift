//
//  FeatureLifecycle.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

// MARK: – FeatureLifecycle
/// A lightweight protocol that unifies the lifecycle interface of all domain "features" (text reading,
/// item search, etc.).  Conforming types are expected to be long-lived, user-facing tasks that can be
/// started, paused/resumed and stopped from outside.
public protocol FeatureLifecycle: AnyObject {
    /// Start or (re)start the feature from the initial state.
    func start()
    /// Temporarily pause the feature without discarding internal state.
    func pause()
    /// Resume a previously paused feature.
    func resume()
    /// Force-stop the feature and reset internal state.
    func stop()

    /// Indicates whether the feature is currently active (running or paused, but not idle).
    var isRunning: Bool { get }
}

// MARK: – Default implementations
public extension FeatureLifecycle {
    func pause() {}
    func resume() {}

    /// Adds the given operation to the featureʼs internal `OperationBag` if available.
    ///   Calling this from any `FeatureLifecycle` conformer avoids boiler-plate in each
    ///   use-case.
    func store(_ op: CancellableOperation) {
        // Use Swift reflection to find a property named "operationBag" of type `OperationBag`.
        // This is safer for pure-Swift types that are not NSObject-derived.
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "operationBag", let bag = child.value as? OperationBag {
                bag.add(op)
                return
            }
        }
    }
} 
