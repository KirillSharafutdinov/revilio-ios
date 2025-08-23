//
//  SessionOrchestrator.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// A lightweight façade that wraps the generic `StateMachine` helper and bundles
/// additional per-session flags such as `isPaused`. It provides a single place
/// responsible for validating state transitions, emitting debug logs and
/// toggling the paused state. Concrete search use-cases compose it rather than
/// owning their own copy-pasted FSM logic.
final class SessionOrchestrator<State: Equatable> {
    // MARK: – Private Properties
    private let stateMachine: StateMachine<State>
    private let logger: Logger
    /// Reactive publisher for state changes. Finishes never.
    private let stateSubject: CurrentValueSubject<State, Never>
    private let pauseSubject = CurrentValueSubject<Bool, Never>(false)
    var statePublisher: AnyPublisher<State, Never> { stateSubject.eraseToAnyPublisher() }
    var pauseStatePublisher: AnyPublisher<Bool, Never> { pauseSubject.eraseToAnyPublisher() }
    /// Indicates that the camera / recognition pipeline is currently halted by
    /// the user while the session (target/query) is kept alive.
    private(set) var isPaused: Bool = false
    
    // MARK: – Public Properties
    /// Current session state (thread-safe).
    var state: State { stateMachine.current() }

    // MARK: - Initialization
    /// - Parameters:
    ///   - initialState: The very first state of the session.
    ///   - label:        Helpful label that will be used when constructing the
    ///                   underlying serial queue of the state-machine.
    ///   - isAllowed:    Validation closure that decides whether a transition
    ///                   from `from` → `to` is permissible.
    ///   - logger:       Optional logger for debugging; defaults to the shared
    ///                   timestamp logger.
    init(initialState: State,
                label: String,
                isAllowed: @escaping (State, State) -> Bool,
                logger: Logger = OSLogger()) {
        self.stateMachine = StateMachine<State>(initial: initialState,
                                                label: label,
                                                validator: isAllowed)
        self.logger = logger
        self.stateSubject = CurrentValueSubject<State, Never>(initialState)
    }

    // MARK: - Public API
    @discardableResult
    func transition(to newState: State) -> Bool {
        let old = stateMachine.current()

        // Early-exit to avoid churning logs with redundant "idle → idle" transitions.
        guard old != newState else {
            logger.log(.debug,
                       "Ignoring no-op transition to the same state: \(newState)",
                       category: "SESSION",
                       file: #file,
                       function: #function,
                       line: #line)
            return false
        }

        let allowed = stateMachine.transition(to: newState)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let prefix = allowed ? "State transition" : "Invalid state transition attempted"
            self.logger.log(.info,
                            "\(prefix): \(old) -> \(newState)",
                            category: "SESSION",
                            file: #file,
                            function: #function,
                            line: #line)
        }
        if allowed {
            stateSubject.send(newState)
        }
        return allowed
    }

    /// Marks the session as paused. Transition validation is left to the
    /// concrete use-case.
    func pause() { isPaused = true; pauseSubject.send(true) }
    /// Resumes a previously paused session.
    func resume() { isPaused = false; pauseSubject.send(false) }
}

// MARK: - State Stream Extension

extension SessionOrchestrator {
    /// Provides an `AsyncStream` mirroring the `statePublisher`.
    /// The stream yields the current state as well as all subsequent state changes
    /// until the caller cancels the iteration. The stream never throws and finishes
    /// when the orchestrator is deallocated.
    func stateStream() -> AsyncStream<State> {
        let publisher = statePublisher
        return AsyncStream<State> { continuation in
            // Relay every published state into the async stream.
            let cancellable = publisher.sink(receiveCompletion: { _ in
                continuation.finish()
            }, receiveValue: { value in
                continuation.yield(value)
            })

            // Cancel the subscription once the stream terminates.
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    /// Provides an `AsyncStream` mirroring the `pauseStatePublisher`.
    /// The stream yields the current paused flag and any subsequent changes.
    func pauseStateStream() -> AsyncStream<Bool> {
        let publisher = pauseStatePublisher
        return AsyncStream<Bool> { continuation in
            let cancellable = publisher.sink(receiveCompletion: { _ in
                continuation.finish()
            }, receiveValue: { value in
                continuation.yield(value)
            })

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
