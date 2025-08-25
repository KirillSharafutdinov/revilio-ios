//
//  OperationBag.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Simple container that owns a collection of `CancellableOperation`s and cancels *all* of them on demand.
/// The bag keeps **strong** references so that Tasks / AnyCancellables live for as long as the bag lives.
public final class OperationBag {
    private var storage: [CancellableOperation] = []
    private let lock = NSLock()

    public init() {}

    public func add(_ op: CancellableOperation) {
        lock.lock(); defer { lock.unlock() }
        storage.append(op)
    }

    public func cancelAll() {
        lock.lock(); let ops = storage; storage.removeAll(); lock.unlock()
        ops.forEach { $0.cancel() }
    }

    deinit {
        cancelAll()
    }
}

// MARK: – Convenience for Combine

public extension AnyCancellable {
    /// Allows using the familiar `.store(in: &bag)` syntax with an `OperationBag`.
    /// The parameter is `inout` only to keep call-sites unchanged; the bag instance
    /// itself is a reference type so the mutation flag is not required.
    func store(in bag: inout OperationBag) {
        bag.add(self)
    }
} 
