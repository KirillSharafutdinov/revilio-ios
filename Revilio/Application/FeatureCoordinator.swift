//
//  FeatureCoordinator.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Public-facing reactive API of `FeatureCoordinator`.  Consumers see only read-only
/// publishers, ensuring encapsulation.
protocol FeatureCoordinating: AnyObject {
    /// Commands issued by Presentation / ViewModel
    func didTapSearchItem()
    func didTapSearchText()
    func didTapReadText()

    /// Reactive outputs
    var processingStatePublisher: AnyPublisher<ProcessingState, Never> { get }
    var isBusyPublisher: AnyPublisher<Bool, Never> { get }

    /// Emits `true` when the underlying use-case is paused and `false` when it resumes.
    var pauseStatePublisher: AnyPublisher<Bool, Never> { get }

    /// Emits whether any use case is currently active (non-idle).
    var isAnyUseCaseActivePublisher: AnyPublisher<Bool, Never> { get }
}

/// A lightweight intermediary between the Presentation layer (controllers / view-models)
/// and the Domain search use-cases. It encapsulates UI interaction policy.
final class FeatureCoordinator: FeatureCoordinating {
    
    // MARK: - Dependencies
    private let searchItemUseCase: SearchItemUseCase
    private let searchTextUseCase: SearchTextUseCase
    private let readTextUseCase: ReadTextUseCase
    /// Centralised authority for mode switching & global termination.
    private let appModeCoordinator: AppModeCoordinating

    // MARK: - Configuration
    /// Generic debounce interval shared by search-item and search-text buttons.
    private let searchDebounceInterval: TimeInterval = Constants.searchDebounceInterval
    /// Dedicated debounce interval for the "Read Text" button (can be zero).
    private let readDebounceInterval: TimeInterval = Constants.readTextDebounceInterval

    // MARK: - State
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isReading: Bool = false
    @Published private(set) var processingState: ProcessingState = .idle
    
    // MARK: - Subjects
    private let itemSubject = PassthroughSubject<Void, Never>()
    private let textSubject = PassthroughSubject<Void, Never>()
    private let readSubject = PassthroughSubject<Void, Never>()
    private let pauseStateSubject = PassthroughSubject<Bool, Never>()

    // MARK: - Publishers
    /// Public-facing publishers (protocol conformance)
    var processingStatePublisher: AnyPublisher<ProcessingState, Never> { $processingState.eraseToAnyPublisher() }
    var isBusyPublisher: AnyPublisher<Bool, Never> {
        Publishers
            .CombineLatest($isSearching, $isReading)
            .map { $0 || $1 }
            .eraseToAnyPublisher()
    }

    var pauseStatePublisher: AnyPublisher<Bool, Never> {
        pauseStateSubject.eraseToAnyPublisher()
    }

    var isAnyUseCaseActivePublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3(
            searchItemUseCase.isActivePublisher,
            searchTextUseCase.isActivePublisher,
            readTextUseCase.isActivePublisher
        )
        .map { $0 || $1 || $2 }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Cancellables
    private var cancellables = OperationBag()
    

    // MARK: - Initialization
    init(searchItemUseCase: SearchItemUseCase,
         searchTextUseCase: SearchTextUseCase,
         readTextUseCase: ReadTextUseCase,
         appModeCoordinator: AppModeCoordinating,) {
        self.searchItemUseCase = searchItemUseCase
        self.searchTextUseCase = searchTextUseCase
        self.readTextUseCase = readTextUseCase
        self.appModeCoordinator = appModeCoordinator

        debouncedTapPublisher(for: itemSubject, interval: searchDebounceInterval)
            .handleEvents(receiveOutput: { [weak self] _ in
                // Centralised termination & mode switch via AppModeCoordinator.
                self?.appModeCoordinator.activate(.searchingItem,
                                                  shouldTerminate: true,
                                                  zoomIndex: -1)
                self?.isSearching = true
                self?.isReading = false
                self?.processingState = .running
            })
            .sink { [weak self] _ in
                // Use unified FeatureLifecycle entry point
                self?.searchItemUseCase.start()
            }
            .store(in: &cancellables)

        debouncedTapPublisher(for: textSubject, interval: searchDebounceInterval)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.appModeCoordinator.activate(.searchingText,
                                                  shouldTerminate: true,
                                                  zoomIndex: -1)
                self?.isSearching = true
                self?.isReading = false
                self?.processingState = .running
            })
            .sink { [weak self] _ in
                self?.searchTextUseCase.start()
            }
            .store(in: &cancellables)

        debouncedTapPublisher(for: readSubject, interval: readDebounceInterval)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.appModeCoordinator.activate(.readingText,
                                                  shouldTerminate: true,
                                                  zoomIndex: -1)
                self?.isReading = true
                self?.isSearching = false
                self?.processingState = .running
            })
            .sink { [weak self] _ in
                self?.readTextUseCase.start()
            }
            .store(in: &cancellables)

        // Observe global stop events via the central StopController.
        StopController.shared.didStopAllPublisher
            .sink { [weak self] _ in
                self?.isSearching = false
                self?.isReading = false
                self?.processingState = .idle
            }
            .store(in: &cancellables)

        // Subscribe to reactive pause/error publishers from each use-case.
        Publishers.MergeMany(
            searchItemUseCase.pauseStatePublisher,
            searchTextUseCase.pauseStatePublisher,
            readTextUseCase.pauseStatePublisher)
            .sink { [weak self] paused in
                self?.pauseStateSubject.send(paused)
                self?.processingState = paused ? .paused : .running
            }
            .store(in: &cancellables)

        // Update processingState on error events (no local pass-through).
        EventBus.shared.publisher
            .compactMap { event -> String? in
                if case let .error(msg) = event { return msg } else { return nil }
            }
            .sink { [weak self] message in
                self?.processingState = .error(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API
    /// Handle tap on the "Search Item" control. Starts a item search.
    /// Forward the gesture event to the underlying `SearchItemUseCase`
    func didTapSearchItem() {
        itemSubject.send(())
    }

    /// Handle tap on the "Search Text" control. Starts a text search.
    /// Forward the gesture event to the underlying `SearchTextUseCase`
    func didTapSearchText() {
        textSubject.send(())
    }

    /// Handle tap on the "Read Text" control. Directly starts the reading use-case
    func didTapReadText() {
        readSubject.send(())
    }

    /// Centralised Combine helper that applies the requested debounce interval and hops to the main queue.
    private func debouncedTapPublisher(for subject: PassthroughSubject<Void, Never>, interval: TimeInterval) -> AnyPublisher<Void, Never> {
        subject
            .debounce(for: .seconds(interval), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
} 
