//
//  CancellableOperation.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// A lightweight abstraction for long-running asynchronous work (Task, AnyCancellable, custom types)
/// that can be cancelled via a common `cancel()` call.  This underpins `OperationBag` which gives
/// every `FeatureLifecycle` a single point of cleanup.
public protocol CancellableOperation {
    func cancel()
}

extension Task: CancellableOperation {}

extension AnyCancellable: CancellableOperation {} 
