//
//  SearchTextUseCase.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine
import UIKit

// MARK: - String Extension

/// Extension for String to find all ranges of a substring
extension String {
    func ranges(of substring: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = self.startIndex
        
        while searchStartIndex < self.endIndex {
            if let range = self.range(of: substring, range: searchStartIndex..<self.endIndex) {
                ranges.append(range)
                searchStartIndex = range.upperBound
            } else {
                break
            }
        }
        
        return ranges
    }
}

// MARK: - TextInputMethod

/// Defines the input method for text search functionality
public enum TextInputMethod: Int, CaseIterable {
    case voice = 0
    case keyboard = 1
} 

/// Manages text search functionality using voice or keyboard input, providing real-time
/// text recognition and haptic feedback. Handles speech recognition, query processing,
/// frame analysis, and state transitions. Supports multiple input methods, auto-off timers,
/// and accessibility features for VoiceOver users.
class SearchTextUseCase: BaseSearchUseCase, FeatureLifecycle {
    // MARK: - Nested Types

    enum SearchState: Equatable {
        case idle
        case listening
        case processingSpeech(text: String)
        case announcing
        case searching(query: String)
        case completed
    }
    
    // MARK: - Public Properties
    var currentSearchQuery: String? {
        switch state {
        case .searching(let query):
            return query
        default:
            return nil
        }
    }
    
    var state: SearchState { orchestrator.state }
    /// Emits the updated pause state (`true` = paused, `false` = active).
    var pauseStatePublisher: AnyPublisher<Bool, Never> { orchestrator.pauseStatePublisher }
    /// Emits the current search state from the orchestrator.
    var statePublisher: AnyPublisher<SearchState, Never> { orchestrator.statePublisher }
    
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
    
    private let currentSearchQuerySubject = CurrentValueSubject<String?, Never>(nil)
    var currentSearchQueryPublisher: AnyPublisher<String?, Never> {
        currentSearchQuerySubject.eraseToAnyPublisher()
    }
    
    var isRunning: Bool {
        switch state {
        case .idle, .completed: return false
        default: return true
        }
    }
    
    var isPaused: Bool { orchestrator.isPaused }
    
    private var startedFromModalWindow: Bool = false
    public var isVoiceOverRunning: Bool
    
    // MARK: - Private Properties
    
    // Dependencies
    private var textRecognizerRepository: TextRecognizerRepository
    private let speechRecognizerRepository: SpeechRecognizerRepository
    private let cameraRepository: CameraRepository
    private let queryAcquirer: ItemQueryAcquiring
    private let feedbackPresenter: FeedbackRepository
    private let feedbackPolicy: FeedbackPolicy
    private let frameProcessor: ContinuousFrameProcessor
    private let alignmentEvaluator: CentreAlignmentEvaluator

    // State Management
    private let orchestrator: SessionOrchestrator<SearchState>
    private var queryTask: Task<Void, Never>? = nil
    private var recognitionTask: Task<Void, Never>? = nil
    private var torchDisposable: AnyCancellable?
    private var operationBag = OperationBag()
    /// Recent searches service for storing successful search terms
    private let recentSearchesService = RecentTextSearchesService.shared
    
    // Auto-off timer
    private var autooffTimer: Timer?
    
    // Speech recognizer work time limit
    private let speechTimeoutInterval: TimeInterval = 10.0
    
    // Combine
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        textRecognizerRepository: TextRecognizerRepository,
        speechRecognizerRepository: SpeechRecognizerRepository,
        cameraRepository: CameraRepository,
        queryAcquirer: ItemQueryAcquiring? = nil,
        feedbackRepository: FeedbackRepository,
        isVoiceOverRunning: Bool,
        logger: Logger = OSLogger()
    ) {
        self.textRecognizerRepository =             textRecognizerRepository
        self.speechRecognizerRepository = speechRecognizerRepository
        self.cameraRepository = cameraRepository
        self.queryAcquirer = queryAcquirer ?? TextQueryAcquisitionService(speechRecognizer: speechRecognizerRepository)
        self.feedbackPresenter = feedbackRepository
        self.isVoiceOverRunning = isVoiceOverRunning
        self.frameProcessor = ContinuousFrameProcessor(cameraRepository: cameraRepository)
        let params = PredictionParameters(center: CGPoint(x: 0.5, y: 0.5),
                                         centerRadius: 0.1,
                                         convictionMax: 10,
                                         convictionInOnDetect: 4,
                                         convictionOutNoDetect: 2,
                                         smoothFactor: 0.1)
        self.alignmentEvaluator = CentreAlignmentEvaluator(predictionParameters: params)
        self.feedbackPolicy = CentreAlignmentFeedbackPolicy(evaluator: alignmentEvaluator,
                                                            searchType: .searchText)

        self.orchestrator = SessionOrchestrator<SearchState>(
            initialState: .idle,
            label: "search-text.state") { from, to in
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

        super.init(predictionParameters: params, logger: logger)

        self.feedbackPresenter.didFinishSpeakingPublisher
            .sink { [weak self] in
                guard let self else { return }
                if case .announcing = self.state, let query = self.currentSearchQuery {
                    _ = self.transitionTo(.searching(query: query))
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

        orchestrator.resume()
    }
    
    // MARK: Public Interface - FeatureLifecycle Conformance

    func start() {
        guard !isRunning else { return }
        FeatureManager.shared.register(self)
        startTextSearch()
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStarted("SearchText"))
    }

    func pause() {
        pauseSearch()
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStopped("SearchText"))
    }

    func resume() {
        resumeSearch()
        FeatureManager.shared.featureStateDidChange()
    }

    func stop() {
        stopSearch()
        FeatureManager.shared.unregister(self)
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStopped("SearchText"))
    }
    
    // MARK: - Public Methods

    /// Start text search with pre-entered text from keyboard input
    /// Bypasses voice recognition and goes directly to text processing
    /// - Parameter text: The text entered via keyboard
    func startTextSearchWithPreenteredText(_ text: String) {
        feedbackPresenter.resume()

        guard !isRunning else { return }

        guard case .idle = state else { return }
        
        startedFromModalWindow = true
                
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            EventBus.shared.send(.error("Search text cannot be empty"))
            return
        }

        guard trimmedText.count <= 100 else {
            EventBus.shared.send(.error("Search text is too long (maximum 100 characters)"))
            return
        }

        let meaningfulChars = trimmedText.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        guard !meaningfulChars.isEmpty else {
            EventBus.shared.send(.error("Search text must contain letters or numbers"))
            return
        }
        
        FeatureManager.shared.register(self)

        prediction.detectionConviction = 0
        prediction.smoothPosition = CGPoint(x: -1.0, y: -1.0)
        
        recentSearchesService.addRecentSearch(trimmedText)
        
        processRecognizedText(trimmedText)
        
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStarted("SearchText"))
    }
    
    // MARK: - Private State Management

    /// Start text search. The recogniser starts listening immediately and the search
    /// begins automatically once a **final** utterance is delivered by the speech engine
    private func startTextSearch() {
        guard case .idle = state else {
            log("ERROR: Cannot start text search – invalid state: \(state)")
            return
        }
        
        feedbackPresenter.resume()
        
        startedFromModalWindow = false

        let voiceOverButtonAnnounceDelay = isVoiceOverRunning ? 1.5 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + voiceOverButtonAnnounceDelay) { [weak self] in
            self?.startSpeechRecognition()
        }
    }
    
    /// Pause the ongoing text search. Stops frame processing and feedback while keeping the
    /// current query intact. Safe to call even if already paused.
    private func pauseSearch() {
        guard case .searching = state, !orchestrator.isPaused else { return }
        cameraRepository.setTorch(active: false, level: 0)
        frameProcessor.stop()
        feedbackPresenter.stopAll()
        recognitionTask?.cancel()
        orchestrator.pause()
    }
    
    /// Resume a previously paused text search.
    private func resumeSearch() {
        guard case .searching = state, orchestrator.isPaused else { return }
        cameraRepository.enableTorchIfUserPrefers(settingKey: "settings.textSearchFlashlight", level: 1.0)
        startFrameProcessing()
        startRecognitionStream()
        orchestrator.resume()
    }
    
    /// Stop the search process
    /// - Parameter shouldStopFeedback: Pass `false` when caller already halted feedback to avoid duplicates.
    private func stopSearch() {
        // Prevent duplicate work – exit early if we are already idle.
        if case .idle = state {
            log("stopSearch() called but session already idle – ignoring duplicate", level: .debug)
            return
        }
        log("Stopping text search")
        
        _ = transitionTo(.idle)
        
        // Stop any ongoing speech session immediately
        operationBag.cancelAll()
        queryAcquirer.cancel()
        
        speechRecognizerRepository.stopRecognition()
        
        feedbackPresenter.stopAndSuspend()

        frameProcessor.stop()
        
        torchDisposable?.cancel()
        torchDisposable = nil
        
        prediction.detectionConviction = 0
        prediction.smoothPosition = CGPoint(x: -1.0, y: -1.0)
        prediction.clearHistory()
        
        orchestrator.resume()
        
        stopAutooffTimer()
        
        log("Search process stopped immediately with complete state reset")
    }
    
    @discardableResult
    private func transitionTo(_ newState: SearchState) -> Bool {
        return orchestrator.transition(to: newState)
    }
    
    // MARK: - Search Processing
    
    /// Start speech recognition
    private func startSpeechRecognition() {
        guard transitionTo(.listening) else {
            return
        }
        
        prediction.detectionConviction = 0
        prediction.smoothPosition = CGPoint(x: -1.0, y: -1.0)
        
        feedbackPresenter.setReadingSpeed(.normal)
        
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let text = try await self.queryAcquirer.acquireQuery(timeout: speechTimeoutInterval)
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
    
    /// Process recognized text and set search query
    /// - Parameter text: The recognized speech text
    private func processRecognizedText(_ text: String) {
        
        guard transitionTo(.processingSpeech(text: text)) else {
            log("ERROR: Cannot process recognized text - invalid state transition")
            return
        }
        
        let lowerResult = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !lowerResult.isEmpty {
            let announcePhrase = Constants.SearchText.announcementPrefix + lowerResult

            if isVoiceOverRunning {
                let voiceOverDelay = startedFromModalWindow ? 2.0 : 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + voiceOverDelay) {
                    UIAccessibility.post(notification: .announcement, argument: announcePhrase) //TODO remove UIKit from domain
                }
            } else {
                self.feedbackPresenter.speak(text: announcePhrase)
            }
            
            _ = transitionTo(.announcing)
            
            setSearchQueryAsync(query: lowerResult)
        } else {
            _ = transitionTo(.idle)
            EventBus.shared.send(.error("No meaningful text provided"))
        }
        
        
    }
    
    /// Set the search query asynchronously
    /// - Parameter query: Text to search for
    private func setSearchQueryAsync(query: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
                        
            self.textRecognizerRepository.setLanguages([Constants.SearchText.recognizerLanguageMain, Constants.SearchText.recognizerLanguageSecondary])
            self.textRecognizerRepository.setMinimumTextHeight(Constants.SearchText.minTextHeight)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                guard self.transitionTo(.searching(query: query)) else {
                    self.log("ERROR: Cannot transition to searching state - invalid transition")
                    return
                }
                
                self.recentSearchesService.addRecentSearch(query.lowercased())
                
                self.startSearchProcess()
            }
        }
    }
    
    /// Start the search process after query has been set
    private func startSearchProcess() {
        orchestrator.resume()
        
        guard case .searching = state else {
            log("ERROR: Cannot start search process - not in searching state")
            return
        }
                
        let wasEnabled = cameraRepository.enableTorchIfUserPrefers(settingKey: "settings.textSearchFlashlight", level: 1.0)
        
        if wasEnabled {
            let disposable = AnyCancellable { [weak self] in
                self?.cameraRepository.setTorch(active: false, level: 0)
            }
            self.store(disposable)
            torchDisposable = disposable
        }
        
        startFrameProcessing()
        
        startRecognitionStream()
        
        startAutooffTimerIfNeeded()
    }
    
    private func handleStateChange(_ state: SearchState) {
        switch state {
        case .searching(let query):
            currentSearchQuerySubject.send(query)
        case .idle, .completed:
            currentSearchQuerySubject.send(nil)
        default:
            break
        }
    }
    
    // MARK: - Frame Processing

    /// Start continuous frame processing for text recognition using `ContinuousFrameProcessor`.
    private func startFrameProcessing() {
        guard case .searching = state else {
            log("ERROR: Cannot start frame processing - not in searching state")
            return
        }

        frameProcessor.start { [weak self] frame in
            guard let self = self else { return }
            self.textRecognizerRepository.processFrame(cameraFrame: frame, accuracy: .accurate)
        }
    }
    
    // MARK: - Recognition Handling

    /// Launches a task that consumes `recognizedTextStream()` until cancelled.
    private func startRecognitionStream() {
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self else { return }
            for await observations in self.textRecognizerRepository.recognizedTextStream() {
                // Heavy processing off the main thread (same strategy as before).
                await Task.detached(priority: .userInitiated) {
                    [weak self] in
                    self?.processTextRecognitionResults(textObservations: observations)
                }.value
            }
        }
        if let task = recognitionTask { self.store(task) }
    }
    
    /// Process text recognition results
    /// - Parameter textObservations: Recognized text observations
    private func processTextRecognitionResults(textObservations: [TextObservation]) {
        guard case .searching(let searchQuery) = state else {
            log("Ignoring text recognition results - not in searching state")
            return
        }

        let matchingObservations = filterMatchingObservations(textObservations, query: searchQuery)

        if matchingObservations.isEmpty && prediction.detectionConviction > 0 {
            prediction.detectionConviction -= prediction.convictionOutNoDetect
            
            if prediction.detectionConviction <= 0 {
                prediction.clearHistory()
            }
        } else if !matchingObservations.isEmpty {
            prediction.detectionConviction += prediction.convictionInOnDetect
            
            if let nearestToCenterObservation = alignmentEvaluator.nearestToCentre(matchingObservations, centerOfItem: { observation in
                self.getTextQueryCenter(observation, query: searchQuery)
            }) {
                let queryCenter = self.getTextQueryCenter(nearestToCenterObservation, query: searchQuery)
                
                if prediction.smoothPosition.x < 0 {
                    prediction.smoothPosition = queryCenter
                } else {
                    prediction.smoothPosition = CGPoint(
                        x: prediction.smoothPosition.x * prediction.smoothFactor + queryCenter.x * (1 - prediction.smoothFactor),
                        y: prediction.smoothPosition.y * prediction.smoothFactor + queryCenter.y * (1 - prediction.smoothFactor)
                    )
                }
                
                prediction.appendPosition(prediction.smoothPosition)
                prediction.appendFrameIndex(prediction.currentFrameIndex)
            }
        }
        
        prediction.clampDetectionConviction()
        
        let feedbackPoint: CGPoint
        if prediction.usePrediction, let predictedPoint = prediction.predictNextPosition() {
            feedbackPoint = predictedPoint
        } else {
            feedbackPoint = prediction.smoothPosition
        }

        if prediction.detectionConviction < prediction.convictionInOnDetect || prediction.smoothPosition.x <= 0 {
            if !feedbackPresenter.isSpeaking {
                feedbackPresenter.stopAll()
            }
        } else {
            let directive = feedbackPolicy.feedback(for: feedbackPoint, feedback: feedbackPresenter)
            feedbackPresenter.play(pattern: directive.pattern, intensity: directive.intensity)
            if let phrase = directive.phrase {
                feedbackPresenter.announce(phrase)
            }
        }
    }
    
    private func filterMatchingObservations(_ textObservations: [TextObservation], query: String) -> [TextObservation] {
        let lowercased = query.lowercased()
        let matches = textObservations.filter { $0.text.lowercased().contains(lowercased) }
        return matches
    }
    
    /// Calculates the visual centre of a concrete **substring match** inside the recognised
    /// text. The algorithm approximates the horizontal position of the substring by
    /// taking its character offset within the full string and projecting that ratio onto the
    /// bounding-box width returned by Vision.
    private func getTextQueryCenter(_ observation: TextObservation, query: String) -> CGPoint {
        let candidateString = observation.text.lowercased()
        let searchString = query.lowercased()

        // Find all occurrences of the query within the candidate string.
        let ranges = candidateString.ranges(of: searchString)
        guard !ranges.isEmpty else {
            // Fallback – no match inside the candidate (shouldn't really happen). Use box centre.
            return CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
        }

        let totalLength = CGFloat(candidateString.count)
        let observationCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)

        var bestCenter = observationCenter
        var minDistance = CGFloat.greatestFiniteMagnitude

        for range in ranges {
            let lower = candidateString.distance(from: candidateString.startIndex, to: range.lowerBound)
            let upper = candidateString.distance(from: candidateString.startIndex, to: range.upperBound)

            let centerOffsetRatio = CGFloat(lower + upper) / 2.0 / totalLength

            let centerX = observation.boundingBox.minX + centerOffsetRatio * observation.boundingBox.width
            let centerY = observation.boundingBox.midY
            let centrePoint = CGPoint(x: centerX, y: centerY)

            let distance = hypot(centrePoint.x - observationCenter.x, centrePoint.y - observationCenter.y)
            if distance < minDistance {
                minDistance = distance
                bestCenter = centrePoint
            }
        }

        return bestCenter
    }
    
    // MARK: - Auto-off Timer Management
    
    /// Starts the auto-off timer based on user preferences, if auto-off is enabled
    private func startAutooffTimerIfNeeded() {
        let autooffIndex = Constants.UserPreferences.textSearchAutooffIndex
        
        guard autooffIndex > 0 else { return }
        
        let timeInterval: TimeInterval = autooffIndex == 1 ? Constants.SearchText.textSearchAutooffSecondary : Constants.SearchText.textSearchAutooffPrimary
        
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
        feedbackPresenter.announce(Constants.SearchText.autooffTriggered)
        feedbackPresenter.play(pattern: .dashPause, intensity: Constants.hapticErrorIntensity)
        
        pause()
    }
}
