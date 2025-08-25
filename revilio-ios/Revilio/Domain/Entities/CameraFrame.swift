//
//  CameraFrame.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Pure-Swift wrapper around a platform-specific camera frame.
/// The `storage` property is intentionally kept `internal` so that only
/// Infrastructure code can down-cast it back to the concrete type
/// (e.g. `CMSampleBuffer`).
public struct CameraFrame: Equatable, Hashable, @unchecked Sendable {
    /// Unique identifier that helps tracing a particular frame through the pipeline.
    public let id: UUID
    /// Capture timestamp expressed as seconds since 1970 to avoid importing `CMTime`.
    public let timestamp: TimeInterval

    /// Opaque reference to the real frame. Only Infrastructure code should
    /// attempt to down-cast it to a platform buffer.
    internal let storage: Any

    /// Creates a new wrapper around an arbitrary frame payload.
    /// - Parameters:
    ///   - storage: The platform-specific frame object (e.g. `CMSampleBuffer`).
    ///   - timestamp: Capture timestamp in seconds. Defaults to `Date().timeIntervalSince1970`.
    public init(storage: Any, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.id = UUID()
        self.timestamp = timestamp
        self.storage = storage
    }

    /// Attempts to unwrap the underlying storage into the requested type.
    /// The method returns `nil` if the cast fails.
    ///
    /// Infrastructure code can use this helper to recover the platform type
    /// while keeping the rest of the codebase free from those imports.
    public func unwrap<T>() -> T? {
        return storage as? T
    }

    // MARK: - Equatable & Hashable (based solely on the unique `id`)

    public static func == (lhs: CameraFrame, rhs: CameraFrame) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 
