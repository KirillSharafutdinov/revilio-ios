//
//  StateMachine.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Thread-safe, generic state machine with optional transition validation.
///
/// Usage:
/// ```swift
/// enum DownloadState { case idle, downloading, finished, failed }
/// let sm = StateMachine(initial: .idle) { from, to in
///     // Return `true` if transition is allowed
///     switch (from, to) {
///     case (.idle, .downloading),
///          (.downloading, .finished),
///          (.downloading, .failed):
///         return true
///     default: return false
///     }
/// }
/// sm.transition(to: .downloading)
/// ```
public final class StateMachine<State: Equatable> {

    /// Current state is accessed through a barrier queue to guarantee consistency.
    public private(set) var state: State
    private let queue: DispatchQueue
    private let canTransition: ((State, State) -> Bool)?

    /// Creates a new StateMachine instance.
    /// - Parameters:
    ///   - initial: The initial state.
    ///   - label: Optional label for the underlying dispatch queue.
    ///   - validator: Closure that validates whether a transition from the first
    ///   state (current) to the second (new) is allowed. If `nil`, every transition
    ///   is considered valid.
    public init(initial: State,
                label: String = "StateMachine.queue",
                validator: ((State, State) -> Bool)? = nil) {
        self.state = initial
        self.queue = DispatchQueue(label: label, attributes: .concurrent)
        self.canTransition = validator
    }

    /// Attempts to transition to a new state.
    /// - Parameter newState: The desired next state.
    /// - Returns: `true` if the transition was applied, `false` otherwise.
    @discardableResult
    public func transition(to newState: State) -> Bool {
        queue.sync(flags: .barrier) {
            let allowed = canTransition?(state, newState) ?? true
            if allowed {
                state = newState
            }
            return allowed
        }
    }

    /// Reads the current state in a thread-safe manner.
    public func current() -> State {
        queue.sync { state }
    }
}

extension StateMachine {
    /// Convenience initializer that receives an explicit list of allowed transitions.
    /// - Note: Works only for `State` types that conform to `Equatable` (already required).
    public convenience init(initial: State,
                            label: String = "StateMachine.queue",
                            allowedTransitions: [(State, State)]) {
        self.init(initial: initial, label: label) { from, to in
            // A transition is allowed when an identical pair exists in the provided array,
            // or when transitioning to the same state (idempotent reset).
            if from == to { return true }
            return allowedTransitions.contains { $0.0 == from && $0.1 == to }
        }
    }
}
