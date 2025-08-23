//
//  UIGestureRecognizer+Combine.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

// MARK: - Combine wrapper for UIGestureRecognizer

extension UIGestureRecognizer {
    /// A Combine publisher emitting the gesture recognizer whenever its state changes to `.began`, `.changed`, or `.recognized`.
    /// Typical usage:
    ///     pinchRecognizer.publisher()
    ///         .filter { $0.state == .ended }
    ///         .sink { ... }
    ///         .store(in: &cancellables)
    public func publisher() -> GesturePublisher {
        GesturePublisher(recognizer: self)
    }

    public struct GesturePublisher: Publisher {
        public typealias Output = UIGestureRecognizer
        public typealias Failure = Never

        fileprivate let recognizer: UIGestureRecognizer

        public func receive<S>(subscriber: S) where S : Subscriber, UIGestureRecognizer == S.Input, Never == S.Failure {
            let subscription = UIGestureRecognizerSubscription(subscriber: subscriber, recognizer: recognizer)
            subscriber.receive(subscription: subscription)
        }
    }
}

// MARK: - Subscription implementation

private final class UIGestureRecognizerSubscription<S: Subscriber>: Subscription where S.Input == UIGestureRecognizer, S.Failure == Never {
    private var subscriber: S?
    weak private var recognizer: UIGestureRecognizer?

    init(subscriber: S, recognizer: UIGestureRecognizer) {
        self.subscriber = subscriber
        self.recognizer = recognizer
        recognizer.addTarget(self, action: #selector(handle))
    }

    func request(_ demand: Subscribers.Demand) {
        // No back-pressure management needed – events fire when recognizer changes state.
    }

    func cancel() {
        subscriber = nil
        recognizer?.removeTarget(self, action: #selector(handle))
    }

    @objc private func handle() {
        guard let recognizer else { return }
        _ = subscriber?.receive(recognizer)
    }
} 
