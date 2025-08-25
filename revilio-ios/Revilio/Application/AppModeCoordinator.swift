//
//  AppModeCoordinator.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import UIKit
import Combine

/// Coordinates high-level application mode/state transitions.
/// Initially provides only a small surface; subsequent slices will extend it with
/// termination, zoom-handling and other responsibilities extracted out of
/// `MainViewModel`.
protocol AppModeCoordinating: AnyObject {
    // MARK: – Reactive outputs
    var currentModePublisher: AnyPublisher<AppMode, Never> { get }
    var buttonStatesPublisher: AnyPublisher<[AppMode: MainViewModel.ButtonState], Never> { get }
    var zoomNamePublisher: AnyPublisher<String, Never> { get }
    /// Emitted whenever zoom index changes; richer alternative to plain name.
    var zoomPresetPublisher: AnyPublisher<ZoomPreset, Never> { get }
    /// Publishes the currently selected reading speed.
    var readingSpeedPublisher: AnyPublisher<ReadingSpeed, Never> { get }
    var uiClearPublisher: AnyPublisher<Void, Never> { get }

    /// High-level processing state that long-running features (search, reading) report.
    var processingStatePublisher: AnyPublisher<ProcessingState, Never> { get }

    /// Indicates whether the app is performing any heavy processing work (speech, detection, etc.).
    var isBusyPublisher: AnyPublisher<Bool, Never> { get }

    /// Emits `true` when a search/reading action is allowed based on current mode & processing state.
    var searchAllowedPublisher: AnyPublisher<Bool, Never> { get }

    // MARK: – Commands
    func activate(_ mode: AppMode, shouldTerminate: Bool, zoomIndex: Int)
    func immediateTermination()
    func resetStateKeepingZoom()

    // Zoom helpers
    func increaseZoom() -> String
    func decreaseZoom() -> String
    func applyCurrentZoom()
    func resetZoomToDefault()

    // Button-state convenience queries
    func setButtonState(for mode: AppMode, state: MainViewModel.ButtonState)
    func resetAllButtonStates(to state: MainViewModel.ButtonState)
    func buttonState(for mode: AppMode) -> MainViewModel.ButtonState

    // Secondary control states (stop/back/next/zoom±/speed)
    var secondaryButtonStatesPublisher: AnyPublisher<[SecondaryButton: MainViewModel.ButtonState], Never> { get }
}

public enum AppMode {
    case idle
    case searchingItem
    case searchingText
    case readingText
}

extension AppMode {
    /// Returns `true` for modes that can initiate search-related actions.
    var isSearchable: Bool {
        switch self {
        case .searchingItem, .searchingText:
            return true
        default:
            return false
        }
    }
}


/// Secondary buttons that are not directly tied to mode selection but still need state updates.
enum SecondaryButton: CaseIterable {
    case stop
    case back
    case next
    case zoomIn
    case zoomOut
    case toggleSpeed
}

/// We reuse `ReadingSpeed` that lives in the Domain layer so Application &
/// Presentation share the same semantic values.  Just bring a local alias for
/// brevity so call-sites don't have to qualify the module.
typealias ReadingSpeedConfig = ReadingSpeed

/// Encapsulates the current zoom selection in a value suitable for publishing.
public struct ZoomPreset: Equatable {
    public let index: Int
    public let name: String
}

/// High-level processing state emitted by SearchCoordinator or other long-running
/// application components.  Keep it UI-friendly; error carries an optional
/// developer-facing message.
public enum ProcessingState: Equatable {
    case idle
    case running
    case paused
    case error(String?)
}

/// Minimal, first-cut implementation.  Only tracks the current mode
/// and mirrors button-state updates through the supplied callbacks.  In the next
/// slices we will move the actual termination logic and zoom management here.
final class AppModeCoordinator: ObservableObject, AppModeCoordinating {
    
    // MARK: – Dependencies
    private let cameraRepository: CameraRepository
    private let speechSynthesizerRepository: SpeechSynthesizerRepository
    private let hapticFeedbackRepository: HapticFeedbackRepository
    private let speechRecognizerRepository: SpeechRecognizerRepository
    private let objectDetectionRepository: ObjectDetectionRepository
    private let textRecognizerRepository: TextRecognizerRepository
    private let searchItemUseCase: SearchItemUseCase
    private let searchTextUseCase: SearchTextUseCase
    private let readTextUseCase: ReadTextUseCase
    
    // MARK: – Published state
    
    @Published private(set) var currentMode: AppMode = .idle
    @Published private var buttonStates: [AppMode: MainViewModel.ButtonState] = [
        .idle: .normal,
        .searchingItem: .normal,
        .searchingText: .normal,
        .readingText: .normal
    ]
    @Published private(set) var currentZoomName: String = Constants.zoomLevelNames[0]
    @Published private(set) var currentZoomPreset: ZoomPreset = ZoomPreset(index: 0, name: Constants.zoomLevelNames[0])
    @Published private(set) var readingSpeed: ReadingSpeed = .normal

    // Processing state aggregated from feature coordinators
    @Published private(set) var processingState: ProcessingState = .idle

    @Published private(set) var isBusy: Bool = false

    // Secondary buttons state map
    @Published private var secondaryButtonStates: [SecondaryButton: MainViewModel.ButtonState] = {
        var dict: [SecondaryButton: MainViewModel.ButtonState] = [:]
        for b in SecondaryButton.allCases { dict[b] = .normal }
        // Stop is disabled on idle by default
        dict[.stop] = .disabled
        dict[.back] = .disabled
        dict[.next] = .disabled
        return dict
    }()

    // MARK: - Private State
    private let zoomLevels: [CGFloat] = Constants.zoomLevels
    private let zoomLevelNames: [String] = Constants.zoomLevelNames
    @Published private var currentZoomIndexInternal: Int = 0
    private var cancellables = OperationBag()

    // Subjects for one-off events
    private let uiClearSubject = PassthroughSubject<Void, Never>()

    // MARK: – Public Publishers (protocol)
    var currentModePublisher: AnyPublisher<AppMode, Never> { $currentMode.eraseToAnyPublisher() }
    var buttonStatesPublisher: AnyPublisher<[AppMode: MainViewModel.ButtonState], Never> { $buttonStates.eraseToAnyPublisher() }
    var zoomNamePublisher: AnyPublisher<String, Never> { $currentZoomName.eraseToAnyPublisher() }
    var zoomPresetPublisher: AnyPublisher<ZoomPreset, Never> { $currentZoomPreset.eraseToAnyPublisher() }
    var readingSpeedPublisher: AnyPublisher<ReadingSpeed, Never> { $readingSpeed.eraseToAnyPublisher() }
    var uiClearPublisher: AnyPublisher<Void, Never> { uiClearSubject.eraseToAnyPublisher() }
    var processingStatePublisher: AnyPublisher<ProcessingState, Never> { $processingState.eraseToAnyPublisher() }
    var isBusyPublisher: AnyPublisher<Bool, Never> { $isBusy.eraseToAnyPublisher() }
    /// Emits `true` when a new search can be started (current mode is searchable & no active processing)
    var searchAllowedPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest($currentMode, $processingState)
            .map { mode, state in
                mode.isSearchable && state == .idle
            }
            .eraseToAnyPublisher()
    }
    var secondaryButtonStatesPublisher: AnyPublisher<[SecondaryButton: MainViewModel.ButtonState], Never> {
        $secondaryButtonStates.eraseToAnyPublisher()
    }

    /// Returns the index that Presentation layer may query for UI highlighting.
    var currentZoomIndex: Int { currentZoomIndexInternal }

    // MARK: - Initialization
    
    init(cameraRepository: CameraRepository,
         speechSynthesizerRepository: SpeechSynthesizerRepository,
         hapticFeedbackRepository: HapticFeedbackRepository,
         speechRecognizerRepository: SpeechRecognizerRepository,
         objectDetectionRepository: ObjectDetectionRepository,
         textRecognizerRepository: TextRecognizerRepository,
         searchItemUseCase: SearchItemUseCase,
         searchTextUseCase: SearchTextUseCase,
         readTextUseCase: ReadTextUseCase) {
        self.cameraRepository = cameraRepository
        self.speechSynthesizerRepository = speechSynthesizerRepository
        self.hapticFeedbackRepository = hapticFeedbackRepository
        self.speechRecognizerRepository = speechRecognizerRepository
        self.objectDetectionRepository = objectDetectionRepository
        self.textRecognizerRepository = textRecognizerRepository
        self.searchItemUseCase = searchItemUseCase
        self.searchTextUseCase = searchTextUseCase
        self.readTextUseCase = readTextUseCase

        // Bind zoom index changes to rich preset publisher and keep name in sync.
        $currentZoomIndexInternal
            .removeDuplicates()
            .sink { [weak self] idx in
                guard let self else { return }
                let name = self.zoomLevelNames[idx]
                self.currentZoomName = name
                self.currentZoomPreset = ZoomPreset(index: idx, name: name)
            }
            .store(in: &cancellables)

        $currentZoomIndexInternal
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] idx in
                guard let self else { return }
                let zoomName = self.zoomLevelNames[idx]

                if let svc = self.speechSynthesizerRepository as? AVSpeechSynthesizerService {
                    svc.resumeOutput()
                }

                // Interrupt any pending utterance so we only announce the latest zoom value.
                self.speechSynthesizerRepository.stopSpeaking()
                self.speechSynthesizerRepository.speak(text: zoomName)
            }
            .store(in: &cancellables)

        // Forward reading-speed changes from Synthesiser service if it supports Combine.
        if let synthCombine = speechSynthesizerRepository as? AVSpeechSynthesizerService {
            synthCombine.readingSpeedPublisher
                .removeDuplicates()
                .sink { [weak self] speed in
                    self?.readingSpeed = speed
                }
                .store(in: &cancellables)

            // Derive busy flag from processing state & TTS activity.
            let recogniserActive = speechRecognizerRepository.statePublisher()
                .map { $0 != .idle }

            let hapticActive = (hapticFeedbackRepository as? CoreHapticsFeedbackManager)?.isActivePublisher ?? Just(false).eraseToAnyPublisher()

            Publishers.CombineLatest4($processingState.map { $0 != .idle },
                                       synthCombine.isSpeakingPublisher,
                                       recogniserActive,
                                       hapticActive)
                .map { procActive, speaking, sttActive, haptic in
                    procActive || speaking || sttActive || haptic
                }
                .assign(to: &$isBusy)
        }

        // Derive mode-button states reactively from `currentMode`.
        $currentMode
            .map { mode -> [AppMode: MainViewModel.ButtonState] in
                var dict: [AppMode: MainViewModel.ButtonState] = [
                    .idle: .normal,
                    .searchingItem: .normal,
                    .searchingText: .normal,
                    .readingText: .normal
                ]
                if mode != .idle {
                    dict[mode] = .active
                }
                return dict
            }
            .assign(to: &$buttonStates)

        // Ensure secondary buttons refresh on every mode change.
        $currentMode
            .sink { [weak self] _ in
                self?.refreshSecondaryStates()
            }
            .store(in: &cancellables)
    }

    // MARK: – Public commands
    
    func activate(_ mode: AppMode, shouldTerminate: Bool, zoomIndex: Int) {
        if shouldTerminate {
            immediateTermination()
        }

        if zoomIndex >= 0 && zoomIndex < zoomLevels.count {
            currentZoomIndexInternal = zoomIndex
            applyCurrentZoom(sideEffectFeedback: false)
        }

        currentMode = mode
    }

    func immediateTermination() {
        StopController.shared.stopAll(reason: .user)

        updateAllButtonStates(to: .normal)
        currentMode = .idle

        uiClearSubject.send()

        refreshSecondaryStates()
    }

    func resetStateKeepingZoom() {
        updateAllButtonStates(to: .normal)
        currentMode = .idle

        uiClearSubject.send()

        refreshSecondaryStates()
    }

    // MARK: - Zoom Management
    
    func increaseZoom() -> String {
        guard currentZoomIndexInternal < zoomLevels.count - 1 else { return zoomLevelNames[currentZoomIndexInternal] }
        currentZoomIndexInternal += 1
        applyCurrentZoom(sideEffectFeedback: true)
        return zoomLevelNames[currentZoomIndexInternal]
    }

    func decreaseZoom() -> String {
        guard currentZoomIndexInternal > 0 else { return zoomLevelNames[currentZoomIndexInternal] }
        currentZoomIndexInternal -= 1
        applyCurrentZoom(sideEffectFeedback: true)
        return zoomLevelNames[currentZoomIndexInternal]
    }

    /// Applies current zoom factor to camera without changing index or producing TTS / haptics.
    /// Presentation layer should call `increaseZoom()` / `decreaseZoom()` rather than this helper.
    func applyCurrentZoom() {
        applyCurrentZoom(sideEffectFeedback: false)
    }
    /// Resets zoom to default (index 0). Speaks the change only if the zoom actually changed.
    func resetZoomToDefault() {
        if currentZoomIndexInternal != 0 {
            currentZoomIndexInternal = 0
            applyCurrentZoom(sideEffectFeedback: true)
        } else {
            // Still ensure camera is at correct factor but without feedback.
            applyCurrentZoom(sideEffectFeedback: false)
        }
    }

    // MARK: - Button State Management
    func setButtonState(for mode: AppMode, state: MainViewModel.ButtonState) {
        updateButtonState(for: mode, state: state)
    }

    func resetAllButtonStates(to state: MainViewModel.ButtonState) {
        updateAllButtonStates(to: state)
    }

    func buttonState(for mode: AppMode) -> MainViewModel.ButtonState {
        return buttonStates[mode] ?? .normal
    }
    
    // MARK: - Private Helpers

    /// Internal helper that optionally produces immediate haptic feedback when the zoom is changed
    /// via a user-initiated action (i.e. direct button tap). The subsequent voice announcement is
    /// still emitted by the debounced Combine pipeline above.
    private func applyCurrentZoom(sideEffectFeedback: Bool) {
        let zoomFactor = zoomLevels[currentZoomIndexInternal]
        cameraRepository.setZoom(factor: zoomFactor)

        if sideEffectFeedback {
            hapticFeedbackRepository.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        }
    }

    private func updateButtonState(for mode: AppMode, state: MainViewModel.ButtonState) {
        buttonStates[mode] = state
    }

    private func updateAllButtonStates(to state: MainViewModel.ButtonState) {
        buttonStates[.searchingItem] = state
        buttonStates[.searchingText] = state
        buttonStates[.readingText] = state
    }

    private func refreshSecondaryStates() {
        // Stop button is enabled in any active mode, disabled when idle
        secondaryButtonStates[.stop] = (currentMode == .idle) ? .disabled : .normal

        // Back / Next & speed toggle are only meaningful while reading text
        let readingActive = currentMode == .readingText
        secondaryButtonStates[.back] = readingActive ? .normal : .disabled
        secondaryButtonStates[.next] = readingActive ? .normal : .disabled
        secondaryButtonStates[.toggleSpeed] = readingActive ? .normal : .disabled

        // Zoom buttons are always available
        secondaryButtonStates[.zoomIn] = .normal
        secondaryButtonStates[.zoomOut] = .normal
    }
}
