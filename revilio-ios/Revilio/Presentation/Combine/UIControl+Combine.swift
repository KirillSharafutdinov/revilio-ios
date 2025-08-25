//
//  UIControl+Combine.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Combine
import UIKit

/// Publisher for UIControl events (touches, value changes, etc.)
extension UIControl {
    /// A Combine publisher that emits whenever the provided UIControlEvents occur.
    public struct EventPublisher: Publisher {
        public typealias Output = UIControl
        public typealias Failure = Never

        fileprivate let control: UIControl
        fileprivate let events: UIControl.Event

        public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
            let subscription = UIControlSubscription(subscriber: subscriber,
                                                    control: control,
                                                    event: events)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher emitting the control itself whenever the specified events occur.
    /// - Parameter events: A `UIControl.Event` set indicating which events should produce a value.
    /// - Returns: A publisher emitting the control whenever the event fires.
    public func publisher(for events: UIControl.Event) -> EventPublisher {
        EventPublisher(control: self, events: events)
    }
}

// MARK: - Subscription implementation

private final class UIControlSubscription<S: Subscriber>: Subscription where S.Input == UIControl, S.Failure == Never {
    private var subscriber: S?
    weak private var control: UIControl?
    private let event: UIControl.Event

    init(subscriber: S, control: UIControl, event: UIControl.Event) {
        self.subscriber = subscriber
        self.control = control
        self.event = event
        control.addTarget(self, action: #selector(handleEvent), for: event)
    }

    func request(_ demand: Subscribers.Demand) {
        // Demand is handled implicitly by „fire on event”, nothing to store.
    }

    func cancel() {
        subscriber = nil
        control?.removeTarget(self, action: #selector(handleEvent), for: event)
    }

    @objc private func handleEvent() {
        guard let control = control else { return }
        _ = subscriber?.receive(control)
    }
}

// MARK: - Convenience for UITextField text changes

extension UITextField {
    /// A publisher that emits the text each time it changes (equivalent to `.editingChanged`).
    public var textPublisher: AnyPublisher<String, Never> {
        NotificationCenter.default
            .publisher(for: UITextField.textDidChangeNotification, object: self)
            .compactMap { ($0.object as? UITextField)?.text }
            .eraseToAnyPublisher()
    }
} 
