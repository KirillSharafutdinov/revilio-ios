//
//  DomainEvent.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine
import os

/// A high-level set of events that describe what is happening inside
/// the domain layer of the application.
///
/// The enum is published through `EventBus.shared` so that individual
/// features can observe application-wide happenings without taking a
/// direct dependency on one another – an implementation of the
/// *Domain Event* pattern.
///
/// - Note: Add new cases sparingly and prefer re-using existing ones
///   where possible to keep the event vocabulary small and consistent.
public enum DomainEvent {
    /// A non-recoverable error occurred inside the domain layer.
    case error(String)
    /// Indicates that a feature has just started executing. The associated
    /// value contains the feature's human-readable identifier.
    case featureStarted(String)
    /// Indicates that a feature has just finished executing. The associated
    /// value contains the feature's human-readable identifier.
    case featureStopped(String)
    /// A general-purpose logging event consisting of a log `LogLevel` and
    /// a human-readable message string.
    case log(LogLevel, String)
}

public final class EventBus {
    public static let shared = EventBus()
    private init() {}
    private let subject = PassthroughSubject<DomainEvent, Never>()

    public func send(_ event: DomainEvent) {
        subject.send(event)
    }

    public var publisher: AnyPublisher<DomainEvent, Never> { subject.eraseToAnyPublisher() }
} 
