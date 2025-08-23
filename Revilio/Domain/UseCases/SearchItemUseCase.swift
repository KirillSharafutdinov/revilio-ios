//
//  SearchItemUseCase.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine
import UIKit

// MARK: - ItemInputMethod

/// Defines the input method for item search functionality
public enum ItemInputMethod: Int, CaseIterable {
    case voice = 0
    case list = 1
}

// MARK: - SearchTarget

/// Lightweight value object describing the target we want to find.
public struct SearchTarget: Equatable, CustomStringConvertible {
    /// Class identifier used inside the Core ML model (e.g. "bicycle", "mouse").
    public let itemName: String
    /// Name of the ML-model bundle that contains the class.
    public let modelName: String

    public init(itemName: String, modelName: String) {
        self.itemName = itemName
        self.modelName = modelName
    }

    public var description: String {
        "SearchTarget(item: \(itemName), model: \(modelName))"
    }
}

/// Manages item search functionality using voice or list selection, providing real-time
/// object detection and haptic feedback. Handles speech recognition, model initialization,
/// frame processing, and state transitions. Supports multiple input methods, auto-off timers,
/// and accessibility features for VoiceOver users.
class SearchItemUseCase: BaseSearchUseCase, FeatureLifecycle {
    
    // MARK: - Nested Types

    enum SearchState: Equatable {
        case idle
        case listening
        case processingSpeech(text: String)
        case announcing
        case searching(target: String)
        case completed
    }
    
    // MARK: - Public Properties

    var currentSearchTarget: String? {
        switch state {
        case .searching(let target):
            return target
        default:
            return nil
        }
    }
    
    var pauseStatePublisher: AnyPublisher<Bool, Never> { orchestrator.pauseStatePublisher }
    
    var statePublisher: AnyPublisher<SearchState, Never> { orchestrator.statePublisher }
    
    private let currentSearchTargetSubject = CurrentValueSubject<String?, Never>(nil)
    var currentSearchTargetPublisher: AnyPublisher<String?, Never> {
        currentSearchTargetSubject.eraseToAnyPublisher()
    }
    
    var isActivePublisher: AnyPublisher<Bool, Never> {
        orchestrator.statePublisher
            .map { state -> Bool in
                switch state {
                case .idle, .completed: return false
                default: return true
                }
            }
            .eraseToAnyPublisher()
    }
    
    var state: SearchState { orchestrator.state }

    /// Returns `true` when the use-case is active (listening, processing or searching).
    /// `.idle` and `.completed` are considered non-running.
    var isRunning: Bool {
        switch state {
        case .idle, .completed: return false
        default: return true
        }
    }
    
    var isPaused: Bool { orchestrator.isPaused }
    
    // MARK: - Private Properties

    // Dependencies
    private var objectDetectionRepository: ObjectDetectionRepository
    private let speechRecognizerRepository: SpeechRecognizerRepository
    private let cameraRepository: CameraRepository
    private let feedbackPresenter: FeedbackRepository
    private let queryAcquirer: ItemQueryAcquiring
    private let modelSelector: ItemModelSelecting
    private let feedbackPolicy: FeedbackPolicy
    private let alignmentEvaluator: CentreAlignmentEvaluator
    private let frameProcessor: ContinuousFrameProcessor
    
    // State Management
    private let orchestrator: SessionOrchestrator<SearchState>
    private var queryTask: Task<Void, Never>? = nil
    private var detectionTask: Task<Void, Never>? = nil
    private var torchDisposable: AnyCancellable?
    private var operationBag = OperationBag()
    
    // Auto-off timer
    private var autooffTimer: Timer?
    
    // Combine cancellables (local)
    private var cancellables = Set<AnyCancellable>()
    
    private var startedFromModalWindow: Bool = false
    public var isVoiceOverRunning: Bool
    
    // Constants
    private let speechTimeoutInterval: TimeInterval = 7.0
    
    // MARK: - Initialization
    
    init(
        objectDetectionRepository: ObjectDetectionRepository,
        speechRecognizerRepository: SpeechRecognizerRepository,
        cameraRepository: CameraRepository,
        feedbackRepository: FeedbackRepository,
        queryAcquirer: ItemQueryAcquiring? = nil,
        modelSelector: ItemModelSelecting = DefaultItemModelSelector(),
        isVoiceOverRunning: Bool,
        logger: Logger = OSLogger()
    ) {
        self.objectDetectionRepository = objectDetectionRepository
        self.speechRecognizerRepository = speechRecognizerRepository
        self.cameraRepository = cameraRepository
        self.queryAcquirer = queryAcquirer ?? SpeechItemQueryAcquisitionService(
            speechRecognizer: speechRecognizerRepository,
            feedbackPresenter: feedbackRepository
        )
        self.modelSelector = modelSelector
        self.isVoiceOverRunning = isVoiceOverRunning
        self.feedbackPresenter = feedbackRepository
        let evaluator = CentreAlignmentEvaluator(predictionParameters: .default)
        self.alignmentEvaluator = evaluator
        self.feedbackPolicy = CentreAlignmentFeedbackPolicy(evaluator: evaluator,
                                                            searchType: .searchObject)
        self.frameProcessor = ContinuousFrameProcessor(
            cameraRepository: cameraRepository,
        )

        self.orchestrator = SessionOrchestrator<SearchState>(
            initialState: .idle,
            label: "search-item.state") { from, to in
                switch (from, to) {
                case (.idle, .listening),
                     (.idle, .processingSpeech),
                     (.listening, .processingSpeech),
                     (.processingSpeech, .announcing),
                     (.announcing, .searching),
                     (.processingSpeech, .searching),
                     (.searching, .completed),
                     (_, .idle):
                    return true
                default:
                    return false
                }
            }

        super.init(predictionParameters: .default, logger: logger)

        self.feedbackPresenter.didFinishSpeakingPublisher
            .sink { [weak self] in
                guard let self else { return }
                if case .announcing = self.state {
                    if let current = self.currentSearchTarget {
                        _ = self.transitionTo(.searching(target: current))
                    }
                }
            }
            .store(in: &cancellables)
        
        orchestrator.statePublisher
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)

        StopController.shared.didStopAllPublisher
            .sink { [weak self] _ in self?.stopSearch() }
            .store(in: &cancellables)
    }
    
    // MARK: Public Interface - FeatureLifecycle Conformance
    
    func start() {
        guard !isRunning else { return }
        FeatureManager.shared.register(self)
        startItemSearch()
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStarted("SearchItem"))
    }

    func pause() {
        pauseSearch()
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStopped("SearchItem"))
    }

    func resume() {
        resumeSearch()
        FeatureManager.shared.featureStateDidChange()
    }

    func stop() {
        stopSearch()
        FeatureManager.shared.unregister(self)
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStopped("SearchItem"))
    }
    
    // MARK: - Public Methods

    /// Start item search with preselected item from list (bypasses voice recognition)
    /// - Parameters:
    ///   - itemName: The localized display name of the item (e.g., "мышь", "велосипед")
    ///   - modelName: The name of the ML model to use
    func startItemSearchWithPreselectedItem(itemName: String, modelName: String) {
        // Mirror public `start()` behaviour so that list-based item selection participates
        // in the central lifecycle handling (StopController, FeatureManager, analytics).
        // Prevent duplicate sessions – if we are already active, ignore the request.
        guard !isRunning else { return }
        
        startedFromModalWindow = true

        FeatureManager.shared.register(self)
        feedbackPresenter.resume()

        prediction.detectionConviction = 0
        prediction.smoothPosition = CGPoint(x: -1.0, y: -1.0)

        feedbackPresenter.setReadingSpeed(.normal)

        processRecognizedText(itemName)
        
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStarted("SearchItem"))
    }
    
    // MARK: - Private State Management
    
    /// Start voice recognition for single press pattern
    private func startItemSearch() {
        feedbackPresenter.resume()
        // === Deferred model warm-up ===
        // Kick off an asynchronous initialisation of the default model so that
        // heavy graph compilation happens in parallel with the speech recogniser.
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.objectDetectionRepository.initialize(modelName: "yolo11mCOCO") // TODO
        }

        guard transitionTo(.listening) else {
            log("Cannot start voice recognition - invalid state transition to listening")
            return
        }
        
        startedFromModalWindow = false
        
        prediction.detectionConviction = 0
        prediction.smoothPosition = CGPoint(x: -1.0, y: -1.0)
        
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let text = try await self.queryAcquirer.acquireQuery(timeout: self.speechTimeoutInterval)
                await MainActor.run {
                    self.processRecognizedText(text)
                }
            } catch {
                await MainActor.run {
                    EventBus.shared.send(.error("Speech recognition error: \(error.localizedDescription)"))
                    _ = self.transitionTo(.idle)
                }
            }
        }
        if let task = queryTask { self.store(task) }
    }
    
    /// Pauses the ongoing search while keeping the current target intact. Does nothing if
    /// the use-case is not in the `.searching` state or if it is already paused.
    private func pauseSearch() {
        guard case .searching = state, !orchestrator.isPaused else { return }
        cameraRepository.setTorch(active: false, level: 0)
        frameProcessor.stop()
        feedbackPresenter.stopAll()
        detectionTask?.cancel()
        orchestrator.pause()
    }

    /// Resumes a previously paused search session. Does nothing if the session is not paused.
    private func resumeSearch() {
        guard case .searching = state, orchestrator.isPaused else { return }
        cameraRepository.enableTorchIfUserPrefers(settingKey: "settings.itemSearchFlashlight", level: 1.0)
        startFrameProcessing()
        startDetectionStream()
        orchestrator.resume()
    }

    /// Stop the current item search immediately and reset internal state.
    /// - Parameter shouldStopFeedback: If `false`, assumes caller already stopped all feedback.
    private func stopSearch(shouldStopFeedback: Bool = true) {
        if case .idle = state {
            return
        }
        _ = transitionTo(.idle)

        operationBag.cancelAll()
        queryTask = nil; detectionTask = nil

        frameProcessor.stop()

        if shouldStopFeedback {
            feedbackPresenter.stopAndSuspend()
        }

        prediction.reset()
        prediction.clearHistory()
        prediction.currentFrameIndex = 0

        torchDisposable?.cancel()
        torchDisposable = nil

        orchestrator.resume()

        queryAcquirer.cancel()
        speechRecognizerRepository.stopRecognition()
        
        stopAutooffTimer()
    }

    @discardableResult
    private func transitionTo(_ newState: SearchState) -> Bool {
        return orchestrator.transition(to: newState)
    }
    
    private func handleStateChange(_ state: SearchState) {
        switch state {
        case .searching(let target):
            currentSearchTargetSubject.send(target)
        case .idle, .completed:
            currentSearchTargetSubject.send(nil)
        default:
            break
        }
    }
    
    // MARK: - Search Processing
    
    /// Process recognized text to find matching item
    /// - Parameter text: The recognized speech text
    private func processRecognizedText(_ text: String) {
        guard transitionTo(.processingSpeech(text: text)) else {
            log("Cannot process recognized text - invalid transition to processing speech state")
            return
        }
        
        let lowerResult = text.lowercased()
        
        var matchedClassId: String?
        var matchedModelName: String?
        var matchedDisplayName: String?

        if let classId = modelSelector.className(for: lowerResult),
           let modelName = modelSelector.modelName(for: lowerResult) {
            matchedClassId = classId
            matchedModelName = modelName
            matchedDisplayName = modelSelector.originalDisplayName(for: lowerResult)
        } else if let fuzzy = modelSelector.partialMatch(for: lowerResult) {
            matchedClassId = fuzzy.classNameInModel
            matchedModelName = fuzzy.modelName
            matchedDisplayName = fuzzy.originalName
        }

        guard let classId = matchedClassId,
              let modelName = matchedModelName,
              let resolvedName = matchedDisplayName else {
            queryAcquirer.cancel()
            _ = transitionTo(.idle)
            log("No matching object found for: '\(text)' (exact or fuzzy)")
            feedbackPresenter.announce(Constants.SearchItem.objectNotSupported)
            return
        }

        let originalName = resolvedName
        
        queryAcquirer.cancel()
        
        let announcePhrase = Constants.SearchItem.announcementPrefix + originalName
        
        if isVoiceOverRunning {
            let voiceOverDelay = startedFromModalWindow ? 2.0 : 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + voiceOverDelay) {
                UIAccessibility.post(notification: .announcement, argument: announcePhrase) //TODO remove UIKit from domain
            }
        } else {
            let modalWindowCloseDelay = startedFromModalWindow ? 1.0 : 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + modalWindowCloseDelay) {
                self.feedbackPresenter.speak(text: announcePhrase)
            }
        }
        
        _ = transitionTo(.announcing)

        setSearchTargetAsync(target: SearchTarget(itemName: classId, modelName: modelName))
        return
    }
    
    /// Set the target item to search for asynchronously
    /// - Parameters:
    ///   - target: The target item to search for
    private func setSearchTargetAsync(target: SearchTarget) {

        // Perform heavy initialisation on a detached background task using structured concurrency.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            self.objectDetectionRepository.initialize(modelName: target.modelName)
            self.objectDetectionRepository.setConfidenceThreshold(0.25)
            self.objectDetectionRepository.setIoUThreshold(0.45)

            switch self.state {
            case .processingSpeech, .announcing:
                break
            default:
                self.log("Search aborted – state changed to \(self.state) before model initialisation completed")
                return
            }

            // Torch handling (unchanged)
            let wasEnabled = self.cameraRepository.enableTorchIfUserPrefers(settingKey: "settings.itemSearchFlashlight", level: 1.0)
            if wasEnabled {
                let disposable = AnyCancellable { [weak self] in
                    self?.cameraRepository.setTorch(active: false, level: 0)
                }
                self.store(disposable)
                self.torchDisposable = disposable
            }

            guard self.transitionTo(.searching(target: target.itemName)) else {
                return
            }

            self.startSearchProcess()
        }
    }
    
    /// Start the search process after target has been set
    private func startSearchProcess() {
        orchestrator.resume()
        startFrameProcessing()
        startDetectionStream()
        startAutooffTimerIfNeeded()
    }
    
    // MARK: - Detection Handling

    private func startFrameProcessing() {
        guard case .searching = state else {
            log("ERROR: Cannot start frame processing - not in searching state")
            return
        }

        frameProcessor.start { [weak self] frame in
            guard let self = self else { return }
            self.objectDetectionRepository.processFrame(cameraFrame: frame)
        }
    }

    private func startDetectionStream() {
        detectionTask?.cancel()
        detectionTask = Task { [weak self] in
            guard let self else { return }
            for await detections in self.objectDetectionRepository.detectionsStream() {
                self.processDetectionResults(detections: detections)
            }
        }
        if let task = detectionTask { self.store(task) }
    }
    
    /// Processes the latest batch of Vision detections and updates prediction / feedback state.
    private func processDetectionResults(detections: [ObjectObservation]) {
        guard case .searching(let targetClass) = state else {
            log("Ignoring detections – not in searching state", level: .debug)
            return
        }

        let matching = detections.filter { $0.label == targetClass }

        if matching.isEmpty {
            if prediction.detectionConviction > 0 {
                prediction.detectionConviction -= prediction.convictionOutNoDetect
            }

            if prediction.detectionConviction <= 0 {
                prediction.clearHistory()
                prediction.currentFrameIndex = 0
            }
        } else {
            prediction.detectionConviction += prediction.convictionInOnDetect

            if let nearest = alignmentEvaluator.nearestToCentre(matching, centerOfItem: { obs in
                CGPoint(x: obs.boundingBox.midX, y: obs.boundingBox.midY)
            }) {
                let centerPoint = CGPoint(x: nearest.boundingBox.midX, y: nearest.boundingBox.midY)

                if prediction.smoothPosition.x < 0 {
                    prediction.smoothPosition = centerPoint
                } else {
                    prediction.smoothPosition = CGPoint(
                        x: prediction.smoothPosition.x * prediction.smoothFactor + centerPoint.x * (1 - prediction.smoothFactor),
                        y: prediction.smoothPosition.y * prediction.smoothFactor + centerPoint.y * (1 - prediction.smoothFactor)
                    )
                }

                prediction.currentFrameIndex += 1
                prediction.appendPosition(prediction.smoothPosition)
                prediction.appendFrameIndex(prediction.currentFrameIndex)
            }
        }

        prediction.clampDetectionConviction()

        let feedbackPoint: CGPoint = {
            if prediction.usePrediction, let predicted = prediction.predictNextPosition() {
                return predicted
            } else {
                return prediction.smoothPosition
            }
        }()

        if prediction.detectionConviction < prediction.convictionInOnDetect || prediction.smoothPosition.x < 0 {
            if !feedbackPresenter.isSpeaking {
                feedbackPresenter.stopAll()
            }
        } else {
            let directive = feedbackPolicy.feedback(for: feedbackPoint, feedback: feedbackPresenter)
            feedbackPresenter.play(pattern: directive.pattern, intensity: directive.intensity)
            if let phrase = directive.phrase {
                // Speak guidance only if the initial "searching for …" phrase has finished.
                if !feedbackPresenter.isSpeaking {
                    feedbackPresenter.announce(phrase)
                }
            }
        }
    }
    
    // MARK: - Auto-off Timer Management
    
    /// Starts the auto-off timer based on user preferences, if auto-off is enabled
    private func startAutooffTimerIfNeeded() {
        let autooffIndex = Constants.UserPreferences.itemSearchAutooffIndex
        
        guard autooffIndex > 0 else { return }

        let timeInterval: TimeInterval = autooffIndex == 1 ? Constants.SearchItem.itemSearchAutooffSecondary : Constants.SearchItem.itemSearchAutooffPrimary
        
        DispatchQueue.main.async { [weak self] in
            self?.stopAutooffTimer()
              
            self?.autooffTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleAutooffTimerExpired()
                }
            }
        }
    }
    
    /// Stops and invalidates the auto-off timer
    private func stopAutooffTimer() {
        autooffTimer?.invalidate()
        autooffTimer = nil
    }
    
    /// Called when the auto-off timer expires
    private func handleAutooffTimerExpired() {
        feedbackPresenter.announce(Constants.SearchItem.autooffTriggered)
        feedbackPresenter.play(pattern: .dashPause, intensity: Constants.hapticErrorIntensity)

        pause()
    }
}

