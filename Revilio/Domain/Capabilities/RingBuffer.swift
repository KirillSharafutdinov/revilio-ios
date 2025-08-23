//
//  RingBuffer.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// A fixed-capacity ring buffer (circular queue) with O(1) append.
/// It purposely avoids `Array.removeFirst()` calls used previously in the prediction history logic.
/// The type is `struct` so it can live on the stack and provide value semantics when needed.
public struct RingBuffer<Element> {
    private var storage: [Element?]
    private var nextIndex: Int = 0
    private(set) public var count: Int = 0

    public let capacity: Int
    
    // MARK: - Initialization

    public init(capacity: Int) {
        precondition(capacity > 0, "Capacity must be greater than zero")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }
    
    // MARK: - Public API

    /// Append a new element, overwriting the oldest when buffer is full.
    public mutating func append(_ element: Element) {
        storage[nextIndex] = element
        nextIndex = (nextIndex + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Current elements in chronological order (oldest → newest).
    public var elements: [Element] {
        guard count > 0 else { return [] }
        let start = (nextIndex - count + capacity) % capacity
        if start + count <= capacity {
            return storage[start..<start+count].compactMap { $0 }
        } else {
            let slice1 = storage[start..<capacity].compactMap { $0 }
            let slice2 = storage[0..<(count - (capacity - start))].compactMap { $0 }
            return slice1 + slice2
        }
    }

    /// Convenience map.
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
        try elements.map(transform)
    }

    public mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        nextIndex = 0
        count = 0
    }
} 
