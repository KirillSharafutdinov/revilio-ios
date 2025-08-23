//
//  ReadTextUseCase.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Helper extension for CGRect center calculation
extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
    // Optimized helper for minimal logging when needed
    var compactDescription: String {
        return String(format: "(%.3f,%.3f,%.3f,%.3f)", origin.x, origin.y, width, height)
    }
}

/// Preferred text reading navigation type chosen by the user.
///
/// - sentences: The text is grouped and divided into sentences based on punctuation marks.
/// - lines: The text is divided into parts according to the objects of the recognized text (usually these are lines).
public enum NavigationType {
    case sentences
    case lines
}

/// Sentence structure for improved reading flow
struct Sentence {
    let text: String
    let textBlocks: [TextBlock]
    let startBlockIndex: Int
    let endBlockIndex: Int
    
    init(text: String, textBlocks: [TextBlock], startBlockIndex: Int, endBlockIndex: Int) {
        self.text = text
        self.textBlocks = textBlocks
        self.startBlockIndex = startBlockIndex
        self.endBlockIndex = endBlockIndex
    }
}

/// Manages text reading functionality using OCR and TTS technologies, providing real-time
/// text recognition, sentence grouping, and speech synthesis. Handles camera stability
/// monitoring, text clustering, and navigation controls for seamless reading experience.
/// Supports multiple languages, punctuation handling, and thermal throttling management.
class ReadTextUseCase: FeatureLifecycle {
    // MARK: - Nested Types
    
    /// Represents the lifecycle of a reading session.
    private enum ReadingState {
        case idle          // No active session
        case capturing     // Collecting camera frames & evaluating quality
        case recognizing   // Best frame selected – waiting for OCR results
        case processed     // OCR complete – reading/navigation in progress
        case paused        // Paused state
    }
    
    // MARK: - Public Properties
    
    /// Toggle to enable/disable detailed DEBUG-level logs at runtime without switching build configuration.
    /// Defaults to `true` (previous behaviour). Set to `false` to silence verbose logs and measure performance.
    var detailedLoggingEnabled: Bool = false
    /// Enables continuous central-cluster detection without TTS (debug visualisation).
    var clusterDebug: Bool = false
    
    var centralClusterPublisher: AnyPublisher<BoundingQuad?, Never> { centralClusterSubject.eraseToAnyPublisher() }
    
    public var sceneStablePublisher: AnyPublisher<Void, Never> { sceneStableSubject.eraseToAnyPublisher() }
    // Derived convenience publishers matching other use-cases' API.
    var isActivePublisher: AnyPublisher<Bool, Never> {
        orchestrator.statePublisher
            .map { $0 != .idle }
            .eraseToAnyPublisher()
    }
    /// Public read-only publisher exposing `navigationEnabledSubject`.
    var navigationEnabledPublisher: AnyPublisher<Bool, Never> {
        navigationEnabledSubject.eraseToAnyPublisher()
    }
    
    var pauseStatePublisher: AnyPublisher<Bool, Never> { orchestrator.pauseStatePublisher }

    var isPaused: Bool { state == .paused }
    
    var isRunning: Bool { state != .idle }
    
    public var isVoiceOverRunning: Bool
    
    // MARK: - Private Properties

    // Repositories
    private var textRecognizerRepository: TextRecognizerRepository
    private let feedbackPresenter: FeedbackRepository
    private let cameraRepository: CameraRepository
    private let frameQualityRepository: FrameQualityRepository
    
    private let logger: Logger

    // State Management
    private var stabilityObserver: CameraStabilityObserver?
    private var torchDisposable: AnyCancellable?
    private var textBlocks: [TextBlock] = []
    private var sentences: [Sentence] = []  // Sentences for sentence-based navigation
    private var currentSentenceIndex: Int = -1  // Current sentence index
    private var navigationType: NavigationType = .sentences
    private var useCentralCluster: Bool = true
    private var centralClusterQuad: BoundingQuad? = nil
    private var centralClusterHideCancellable: AnyCancellable?
    private var lastNavigationWasRewind: Bool = false
    private var hasProvidedEndFeedback: Bool = false
    private var pausedRemainingText: String?
    /// Number of upcoming `didFinish` callbacks that should be ignored because they were
    /// triggered by a manual interruption (stop/next/previous/stop-reading).
    private var pendingDidFinishIgnores: Int = 0
    /// Pre-compiled regular expression used by `convertTextForSpeech(_)`. Compiling a
    /// regex is relatively costly (~1–2 ms) so caching it shaves a measurable chunk
    /// off our background processing budget.
    private static let singleCapitalRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "\\b[A-Z]\\b", options: [])
    }()
    /// Base delay after switching on the torch so AE can converge.
    /// after field-testing on iPhone 14 / 15 where AE stabilises in <0.5 s.
    private let flashDelay: TimeInterval = 0.4
    
    // Grid Processing
    private let gridSize: Int = Constants.ReadText.gridSize
    private var textGrid: [[GridCell]] = []
    /// Current requirement for the minimum number of sharp cells a frame must have.
    /// Initialised on the first captured frame to the half of total cell count (e.g. 5000 for a 100×100 grid).
    private var currentMinNumberOfSharpCells: Double = 0.0
    /// Factor by which `currentMinNumberOfSharpCells` is reduced every time none of the
    /// stored frames meet the requirement
    private let minNumberOfSharpCellsReducingFactor: Double = Constants.ReadText.minNumberOfSharpCellsReducingFactor
    private var capturedSharpnessFrames: [(frame: CameraFrame, data: FrameSharpnessData)] = []
    /// Access to `textGrid` is protected by `gridQueue` to ensure thread-safety
    private let gridQueue = DispatchQueue(label: "read-text.grid", qos: .userInitiated, attributes: .concurrent)
    
    // Combine
    private var cancellables = Set<AnyCancellable>()
    private let centralClusterSubject = PassthroughSubject<BoundingQuad?, Never>()
    private let sceneStableSubject = PassthroughSubject<Void, Never>()
    /// Publishes whether the current session contains recognised text that can be navigated
    private let navigationEnabledSubject = CurrentValueSubject<Bool, Never>(false)

    // Operations
    private var recognitionTask: Task<Void, Never>? = nil
    private var operationBag = OperationBag()
    
    // MARK: - State Machine

    private lazy var orchestrator: SessionOrchestrator<ReadingState> = { [unowned self] in
        return SessionOrchestrator<ReadingState>(
            initialState: .idle,
            label: "read-text.state",
            isAllowed: { from, to in
                switch (from, to) {
                // Regular lifecycle
                case (.idle, .capturing),
                     (.capturing, .recognizing),
                     (.recognizing, .processed),
                     (.recognizing, .idle), // allow immediate full stop during OCR phase

                // Recovery paths / retries
                     (.recognizing, .capturing),
                     (.capturing, .idle),
                     (.processed, .idle),
                     (.processed, .capturing),

                // Pause / resume
                     (.processed, .paused),
                     (.paused, .processed),
                     (.paused, .idle):
                    return true
                default:
                    return false
                }
            })
    }()
    /// Convenience accessor for current state powered by the orchestrator.
    private var state: ReadingState { orchestrator.state }
    
    // MARK: - Initialization

    init(
        textRecognizerRepository: TextRecognizerRepository,
        feedbackRepository: FeedbackRepository,
        cameraRepository: CameraRepository,
        frameQualityRepository: FrameQualityRepository,
        isVoiceOverRunning: Bool,
        logger: Logger = OSLogger()
    ) {
        self.textRecognizerRepository = textRecognizerRepository
        self.feedbackPresenter = feedbackRepository
        self.cameraRepository = cameraRepository
        self.frameQualityRepository = frameQualityRepository
        self.isVoiceOverRunning = isVoiceOverRunning
        self.logger = logger
        
        initializeGrid()

        self.feedbackPresenter.didFinishSpeakingPublisher
            .sink { [weak self] in
                self?.handleSpeechFinished()
            }
            .store(in: &cancellables)

        StopController.shared.didStopAllPublisher
            .sink { [weak self] _ in self?.stopReading() }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API - FeatureLifecycle Conformance

    func start() {
        FeatureManager.shared.register(self)
        startReading()
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStarted("ReadText"))
    }

    func pause() {
        pauseReading()
        FeatureManager.shared.featureStateDidChange()
    }

    func resume() {
        let voiceOverButtonAnnounceDelay = isVoiceOverRunning ? 0.9 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + voiceOverButtonAnnounceDelay) { [weak self] in
            self?.resumeReading()
        }

        FeatureManager.shared.featureStateDidChange()
    }

    func stop() {
        stopReading()
        FeatureManager.shared.unregister(self)
        FeatureManager.shared.featureStateDidChange()
        EventBus.shared.send(.featureStopped("ReadText"))
    }
    
    // MARK: - Public Navigation Methods

    func speakNextBlock() {
        updatePauseState(false)

        hasProvidedEndFeedback = false
        
        lastNavigationWasRewind = false
        
        let voiceOverButtonAnnounceDelay = isVoiceOverRunning ? 0.8 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + voiceOverButtonAnnounceDelay) { [weak self] in
            self?.speakAtOffset(1)
        }
    }
    
    func speakPreviousBlock() {
        updatePauseState(false)

        hasProvidedEndFeedback = false
        
        lastNavigationWasRewind = true
        
        let voiceOverButtonAnnounceDelay = isVoiceOverRunning ? 0.8 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + voiceOverButtonAnnounceDelay) { [weak self] in
            self?.speakAtOffset(-1)
        }
    }

    // MARK: - Private State Management
    
    private func startReading() {
        if isRunning {
            log("startReading(): Active session detected – performing implicit stop before restart")
            stopReading()
            pendingDidFinishIgnores = 0
        }

        // No recognised text yet – disable navigation until OCR results arrive.
        navigationEnabledSubject.send(false)

        // Reset any outstanding suppressions from previous sessions **before** resuming.
        pendingDidFinishIgnores = 0

        feedbackPresenter.resume()
        guard transitionTo(.capturing) else { return }
        
        if !isVoiceOverRunning{
            feedbackPresenter.speak(text: Constants.ReadText.announcement)
        }
        
        textBlocks = []
        sentences = []
        currentSentenceIndex = -1
        lastNavigationWasRewind = false
        hasProvidedEndFeedback = false
        pausedRemainingText = nil
        
        textRecognizerRepository.setLanguages([Constants.SearchText.recognizerLanguageMain, Constants.SearchText.recognizerLanguageSecondary])
        textRecognizerRepository.setMinimumTextHeight(Constants.ReadText.minTextHeight)
        
        let enabled = cameraRepository.enableTorchIfUserPrefers(settingKey: "settings.textReadingFlashlight", level: 0.3)
        if enabled {
            let disposable = AnyCancellable { [weak self] in
                self?.cameraRepository.setTorch(active: false, level: 0)
            }
            self.store(disposable)
            torchDisposable = disposable
        }
        startStabilityMonitoring()
        
        startRecognitionStream()
        
        currentMinNumberOfSharpCells = 0.0
        
        // Fetch the current reading navigation preference once per session.
        // 0 = lines, 1 = sentences.
        let readingNavigationIndex = Constants.UserPreferences.textReadingNavigationIndex
        navigationType = (readingNavigationIndex == 0) ? .lines : .sentences

        // Fetch the current reading area preference once per session.
        // 0 = whole frame, 1 = page (central cluster only).
        let readingMethodIndex = Constants.UserPreferences.textReadingMethodIndex
        useCentralCluster = (readingMethodIndex == 1)
    }
    
    /// Pause the ongoing speech immediately. Keeps the current navigation index so that `resumeReading()` will
    /// continue from the exact same sentence / paragraph. Does nothing if the session is already paused or inactive.
    private func pauseReading() {
        guard isRunning, !isPaused else { return }
        pausedRemainingText = feedbackPresenter.pauseSpeaking()
        updatePauseState(true)
    }
    
    /// Resume speech from the point where it was previously paused. Does nothing if the session is not paused.
    private func resumeReading() {
        guard isRunning, isPaused else { return }
        updatePauseState(false)
        if let fragment = pausedRemainingText {
            feedbackPresenter.speak(text: fragment)
            pausedRemainingText = nil
        } else if lastNavigationWasRewind {
            speakAtOffset(1)
            lastNavigationWasRewind = false
        } else {
            speakAtCurrentIndex()
        }
    }
    
    /// Stop reading process
    /// - Parameter shouldStopFeedback: Pass `false` if a higher-level component already stopped all feedback.
    private func stopReading(shouldStopFeedback: Bool = true) {
        if case .idle = state {
            log("stopReading() called but already idle – ignoring duplicate", level: .debug)
            return
        }

        if shouldStopFeedback {
            pendingDidFinishIgnores += 1
            feedbackPresenter.stopAndSuspend()
        }
        
        operationBag.cancelAll()
        
        resetState()
        
        torchDisposable?.cancel(); torchDisposable = nil
    }
    
    /// Reset internal state
    private func resetState() {
        guard transitionTo(.idle) else {
            log("Error transition to .idle", level: .debug)
            return
        }
        
        textBlocks.removeAll()
        sentences.removeAll()
        currentSentenceIndex = 0
        
        lastNavigationWasRewind = false
        hasProvidedEndFeedback = false
        
        stabilityObserver?.invalidate()
        stabilityObserver = nil
        
        clearGrid()
        centralClusterQuad = nil
        cancelCentralClusterAutoHide()
        centralClusterSubject.send(nil)
        
        capturedSharpnessFrames.removeAll()
        currentMinNumberOfSharpCells = 0.0
        
        torchDisposable?.cancel(); torchDisposable = nil
        
        recognitionTask?.cancel()

        // Ensure future sessions start clean without leftover suppressions.
        pendingDidFinishIgnores = 0

        // No text available after reset – disable navigation.
        navigationEnabledSubject.send(false)
    }
    
    /// Centralised helper that toggles the paused flag via the shared `SessionOrchestrator` and
    /// performs the matching state-machine transition so that internal logic stays consistent.
    private func updatePauseState(_ paused: Bool) {
        if paused {
            orchestrator.pause()
            _ = transitionTo(.paused)
        } else {
            orchestrator.resume()
            _ = transitionTo(.processed)
        }
    }
    
    /// Attempts a validated state transition via the orchestrator.
    @discardableResult
    private func transitionTo(_ newState: ReadingState) -> Bool {
        return orchestrator.transition(to: newState)
    }
    
    // MARK: - Speech Handling

    private func speakAtOffset(_ offset: Int) {
        guard !sentences.isEmpty else { return }
        
        guard isRunning else { return }
        
        if feedbackPresenter.isSpeaking {
            feedbackPresenter.stopAll()
        }
        
        let newIndex = currentSentenceIndex + offset
        
        if newIndex < 0 {
            feedbackPresenter.play(pattern: .continuous, intensity: 1.0)
            currentSentenceIndex = 0
            hasProvidedEndFeedback = false
            
            lastNavigationWasRewind = false
        } else if newIndex >= sentences.count {
            feedbackPresenter.play(pattern: .continuous, intensity: 1.0)
            currentSentenceIndex = sentences.count - 1
            hasProvidedEndFeedback = true
            return
        } else {
            currentSentenceIndex = newIndex
            hasProvidedEndFeedback = false
        }
        
        speakAtCurrentIndex()
    }
    
    private func speakAtCurrentIndex() {
        guard currentSentenceIndex >= 0, currentSentenceIndex < sentences.count else {
            return
        }

        let sentence = sentences[currentSentenceIndex]
        if !sentence.text.isEmpty {
            let convertedText = convertTextForSpeech(sentence.text)
            log("SPEECH: Playing sentence \(currentSentenceIndex + 1)/\(sentences.count): '\(sentence.text)' -> '\(convertedText)'")
            DispatchQueue.main.async {
                self.feedbackPresenter.speak(text: convertedText)
            }
        }
    }
    
    /// Converts text for better speech synthesis
    /// - Replaces quotation marks « and » with commas
    /// - Replaces single capital letters with space, lowercase letter, comma (e.g., "C" -> " c,")
    private func convertTextForSpeech(_ text: String) -> String {
        var convertedText = text
        
        convertedText = convertedText.replacingOccurrences(of: "«", with: ",")
        convertedText = convertedText.replacingOccurrences(of: "»", with: ",")
        
        // Handle single capital letters – the regex is expensive to build, cache it
        // across invocations to avoid repeated compilation cost.
        let range = NSRange(location: 0, length: convertedText.utf16.count)
        let matches = ReadTextUseCase.singleCapitalRegex.matches(in: convertedText,
                                                                 options: [],
                                                                 range: range)
        for match in matches.reversed() {
            let matchRange = match.range
            if let swiftRange = Range(matchRange, in: convertedText) {
                let capitalLetter = String(convertedText[swiftRange])
                let lowercaseLetter = capitalLetter.lowercased()
                let replacement = " \(lowercaseLetter),"
                convertedText.replaceSubrange(swiftRange, with: replacement)
            }
        }
        
        // Clean up any double spaces or commas that might have been created
        convertedText = convertedText.replacingOccurrences(of: "  ", with: " ")
        convertedText = convertedText.replacingOccurrences(of: ",,", with: ",")
        convertedText = convertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return convertedText
    }
    
    private func handleSpeechFinished() {
        guard isRunning else { return }
        
        if pendingDidFinishIgnores > 0 {
            pendingDidFinishIgnores -= 1
            return
        }

        if lastNavigationWasRewind {
            updatePauseState(true)
        } else {
            if currentSentenceIndex < sentences.count - 1 {
                currentSentenceIndex += 1
                hasProvidedEndFeedback = false
                speakAtCurrentIndex()
            } else if sentences.isEmpty && state == .processed {
                stop()
            } else if !hasProvidedEndFeedback && state == .processed {
                feedbackPresenter.play(pattern: .continuous, intensity: 1.0)
                hasProvidedEndFeedback = true
                updatePauseState(true)
            }
        }
    }

    // MARK: - Text Recognition Processing

    /// Launches a task that consumes recognized text observations via AsyncStream.
    private func startRecognitionStream() {
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self else { return }
            for await observations in self.textRecognizerRepository.recognizedTextStream() {
                // Heavy clustering off-thread to keep UI responsive.
                await Task.detached(priority: .userInitiated) { [weak self] in
                    self?.processTextRecognitionResults(textObservations: observations)
                }.value
            }
        }
        if let task = recognitionTask { self.store(task) }
    }
    
    private func processTextRecognitionResults(textObservations: [TextObservation]) {
        guard state == .recognizing else { return }
        
        logAllRecognizedObservations(textObservations)
        
        // --- Second-stage veto: low OCR confidence -------------------------
        let confidences = textObservations.map { $0.confidence }.sorted()
        if let medianConf = confidences.dropFirst(confidences.count / 2).first,
           medianConf < 0.4 {
            log(String(format: "VETO: median OCR confidence %.2f < 0.4 – discarding frame", medianConf))
            if transitionTo(.capturing) {
                startStabilityMonitoring()
            }
            return
        }

        let shouldRunGridPass = useCentralCluster && textObservations.count >= Constants.ReadText.minNumberOfObservationsForClustering

        if shouldRunGridPass {
            clearGrid()
            markTextInGrid(from: textObservations)
            // Debug: visualise the populated text grid
            logTextGrid()

            let boolGrid = textGrid.map { $0.map { $0.hasText } }
            centralClusterQuad = CentralTextClusterDetector(
                grid: boolGrid,
                emptyThreshold: Constants.ReadText.clusterEmptyThreshold,
                vertGap: Constants.ReadText.clusterVerticalGap,
                horizGap: Constants.ReadText.clusterHorizontalGap,
                diagDegreeStep: Constants.ReadText.clusterDiagonalDegreeStep,
                diagSteps: Constants.ReadText.clusterDiagonalSteps,
                log: { [weak self] message in self?.log(message) }
            ).detect()
            centralClusterSubject.send(centralClusterQuad)
            scheduleCentralClusterAutoHide()
        } else {
            centralClusterQuad = nil
            cancelCentralClusterAutoHide()
            centralClusterSubject.send(nil)
        }
        
        // Step 2: Filter observations using the built cluster rectangle
        let clusteredObservations: [TextObservation]
        if let quad = centralClusterQuad {
            clusteredObservations = filterObservations(to: quad, observations: textObservations)
        } else {
            clusteredObservations = textObservations
        }
        
        logFilteringResults(originalObservations: textObservations, filteredObservations: clusteredObservations)
        
        textBlocks = clusteredObservations
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY } // Sort top-to-bottom for proper sentence detection
            .map { TextBlock.from(observation: $0) }
        
        sentences = groupTextBlocksIntoSentences(textBlocks)

        // Update navigation availability publisher
        navigationEnabledSubject.send(!sentences.isEmpty)

        _ = transitionTo(.processed)
        
        let delayForAnnounce = feedbackPresenter.isSpeaking ? 1.0 : 0.0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delayForAnnounce) { [weak self] in
            guard let self = self else { return }

            if !self.sentences.isEmpty {
                self.currentSentenceIndex = 0
                self.speakAtCurrentIndex()
            } else {
                feedbackPresenter.play(pattern: .continuous, intensity: 1.0)
                DispatchQueue.main.async {
                    self.feedbackPresenter.speak(text: Constants.ReadText.textNotDetected)
                }
            }
        }
        
        if !shouldRunGridPass {
            cancelCentralClusterAutoHide()
            centralClusterSubject.send(nil)
        }

        // In debug mode we only want to continuously update the cluster overlay.
        if clusterDebug {
            // Immediately restart capturing for the next frame after broadcasting overlay.
            if transitionTo(.capturing) {
                capturedSharpnessFrames.removeAll()
                currentMinNumberOfSharpCells = 0.0 // will re-init on first candidate
                startStabilityMonitoring()
            }
            return // skip further processing (sentence grouping & TTS)
        }
    }
    
    // MARK: - Sentence Detection
    
    private func groupTextBlocksIntoSentences(_ textBlocks: [TextBlock]) -> [Sentence] {
        guard !textBlocks.isEmpty else { return [] }
        
        switch navigationType {
            case .lines:
                return textBlocks.enumerated().map { (index, block) in
                    Sentence(
                        text: block.text,
                        textBlocks: [block],
                        startBlockIndex: index,
                        endBlockIndex: index
                    )
                }
                
            case .sentences:
            // Threshold (in Vision normalised units) that we consider a hard break between logical lines/sections.
            let verticalGapThreshold: CGFloat = 0.02
            let sentenceTerminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
            
            var combinedText = ""
            var previousBlock: TextBlock? = nil
            
            for block in textBlocks {
                let blockText = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !blockText.isEmpty else { continue }
                
                // If there is a sizeable vertical gap from the previous text block, force a sentence break.
                if let prev = previousBlock {
                    let gap = abs(prev.boundingBox.rect.minY - block.boundingBox.rect.maxY)
                    if gap > verticalGapThreshold {
                        // Inject a period if the last character is not already a terminator
                        if let last = combinedText.last, !sentenceTerminators.contains(last) {
                            combinedText += "."
                        }
                        if !combinedText.hasSuffix(" ") {
                            combinedText += " "
                        }
                    }
                }
                
                if !combinedText.isEmpty && !combinedText.hasSuffix(" ") {
                    combinedText += " "
                }
                combinedText += blockText
                previousBlock = block
            }
            
            let sentenceTexts = splitTextIntoSentences(combinedText)
            var sentences: [Sentence] = []
            for sentenceText in sentenceTexts where !sentenceText.isEmpty {
                sentences.append(Sentence(
                    text: sentenceText,
                    textBlocks: textBlocks,
                    startBlockIndex: 0,
                    endBlockIndex: textBlocks.count - 1))
            }
            return sentences
        }
    }
    
    private func splitTextIntoSentences(_ text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }
        
        var sentences: [String] = []
        var currentSentence = ""
        var i = trimmedText.startIndex
        
        while i < trimmedText.endIndex {
            let char = trimmedText[i]
            currentSentence.append(char)
            
            if isSentenceEnder(char) {
                // Look ahead to handle multiple punctuation marks (like "..." or "?!")
                var nextIndex = trimmedText.index(after: i)
                while nextIndex < trimmedText.endIndex {
                    let nextChar = trimmedText[nextIndex]
                    if isSentenceEnder(nextChar) {
                        currentSentence.append(nextChar)
                        nextIndex = trimmedText.index(after: nextIndex)
                    } else {
                        break
                    }
                }
                i = nextIndex
                
                let trimmedSentence = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSentence.isEmpty && !isLikelyAbbreviation(trimmedSentence) {
                    sentences.append(trimmedSentence)
                    currentSentence = ""
                } else if isLikelyAbbreviation(trimmedSentence) {
                    // If it's an abbreviation, don't end the sentence yet
                    // Just continue to the next character
                }
                
                // Skip whitespace after sentence ending
                while i < trimmedText.endIndex && trimmedText[i].isWhitespace {
                    if !currentSentence.isEmpty {
                        currentSentence.append(" ")
                    }
                    i = trimmedText.index(after: i)
                }
                continue
            }
            
            i = trimmedText.index(after: i)
        }
        
        // Add any remaining text as a final sentence
        let remainingSentence = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainingSentence.isEmpty {
            sentences.append(remainingSentence)
        }
        
        return sentences
    }
    
    private func isSentenceEnder(_ char: Character) -> Bool {
        let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？"]
        return sentenceEnders.contains(char)
    }
    
    private func isLikelyAbbreviation(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it ends with a period and is short with uppercase letters
        if trimmedText.hasSuffix(".") && trimmedText.count <= 5 {
            let uppercaseCount = trimmedText.filter({ $0.isUppercase }).count
            if uppercaseCount > 0 {
                return true
            }
        }
        
        // Common abbreviations TODO
        let commonAbbreviations = ["Mr.", "Dr.", "Mrs.", "Ms.", "Prof.", "Inc.", "Ltd.", "Co.", "etc.", "vs.", "Jr.", "Sr."]
        return commonAbbreviations.contains(trimmedText)
    }
    
    // MARK: - Central Cluster & Grid Management
    
    private func initializeGrid() {
        guard gridSize > 0 && gridSize <= 200 else {
            return
        }
        
        textGrid = Array(0..<gridSize).map { row in
            Array(0..<gridSize).map { col in
                GridCell(row: row, col: col)
            }
        }
    }
    
    private func clearGrid() {
        gridQueue.sync(flags: .barrier) {
            guard !textGrid.isEmpty && textGrid.count == gridSize else {
                initializeGrid(); return
            }
            
            for row in 0..<gridSize {
                for col in 0..<gridSize {
                    textGrid[row][col].hasText = false
                }
            }
            
            centralClusterQuad = nil
        }
    }
    
    private func markTextInGrid(from observations: [TextObservation]) {
        gridQueue.sync(flags: .barrier) {
            for observation in observations {
                // Convert bounding box to grid coordinates using overlap-based approach
                let boundingBox = observation.boundingBox
                
                // Calculate the actual grid range that this bounding box overlaps
                // Vision coordinates: (0,0) at bottom-left, grid: (0,0) at top-left
                let visionMinY = boundingBox.minY
                let visionMaxY = boundingBox.maxY
                let visionMinX = boundingBox.minX
                let visionMaxX = boundingBox.maxX
                
                // Convert to grid coordinates (flip Y axis)
                let gridMinRow = Int((1.0 - visionMaxY) * Double(gridSize))
                let gridMaxRow = Int((1.0 - visionMinY) * Double(gridSize))
                let gridMinCol = Int(visionMinX * Double(gridSize))
                let gridMaxCol = Int(visionMaxX * Double(gridSize))
                
                // Clamp to grid bounds and ensure at least one cell is marked
                let clampedMinRow = max(0, min(gridMinRow, gridSize - 1))
                let clampedMaxRow = max(clampedMinRow, min(gridMaxRow, gridSize - 1))
                let clampedMinCol = max(0, min(gridMinCol, gridSize - 1))
                let clampedMaxCol = max(clampedMinCol, min(gridMaxCol, gridSize - 1))
                
                // Mark all overlapping cells
                for row in clampedMinRow...clampedMaxRow {
                    for col in clampedMinCol...clampedMaxCol {
                        textGrid[row][col].hasText = true
                    }
                }
            }
        }
    }
    
    /// Keeps only the observations whose bounding-box **centre** falls inside the rectangle
    /// returned by `CentralClusterDetector`.
    private func filterObservations(to quad: BoundingQuad?, observations: [TextObservation]) -> [TextObservation] {
        guard let quad = quad else { return observations }
        return observations.filter { quad.contains($0.boundingBox.center) }
    }
    
    /// Helper: schedules automatic hiding of the central-cluster overlay after 2 s
    private func scheduleCentralClusterAutoHide() {
        // Cancel any existing timer to avoid overlapping tasks
        centralClusterHideCancellable?.cancel()
        centralClusterHideCancellable = Just(())
            .delay(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.centralClusterSubject.send(nil)
                // Invalidate the token after firing
                self?.centralClusterHideCancellable?.cancel()
                self?.centralClusterHideCancellable = nil
            }
    }
    
    /// Helper: cancels the pending auto-hide, e.g. when overlay is cleared earlier
    private func cancelCentralClusterAutoHide() {
        centralClusterHideCancellable?.cancel()
        centralClusterHideCancellable = nil
    }

    // MARK: - Quality & Stability helpers

    private func startStabilityMonitoring() {
        guard isRunning, state == .capturing else {
            log("STABILITY: Skipping monitoring – current state \(state)")
            return
        }
        
        if let existingMonitor = stabilityObserver as? CameraStabilityMonitor {
            log("STABILITY: Reusing existing monitor")
            existingMonitor.reset()
            subscribeToStabilityEvents(monitor: existingMonitor)
            existingMonitor.start()
            return
        }

        let monitor = CameraStabilityMonitor(device: cameraRepository.captureDevice,
                                             consecutiveStableFrames: Constants.ReadText.requiredStableFrames,
                                             lensDeltaTolerance: Constants.ReadText.lensDeltaTolerance,
                                             exposureTolerance: Constants.ReadText.exposureTolerance)
        monitor.onSceneStable = { [weak self] in
            self?.captureCandidateFrame()
        }

        subscribeToStabilityEvents(monitor: monitor)
        stabilityObserver = monitor
        monitor.start()
    }

    /// Subscribes to the given monitorʼs `stabilityPublisher` and forwards
    /// the signal to `sceneStableSubject` for consumption by UI layers.
    private func subscribeToStabilityEvents(monitor: CameraStabilityMonitor) {
        let cancellable = monitor.stabilityPublisher
            .sink { [weak self] _ in
                self?.sceneStableSubject.send()
            }
        self.store(cancellable)
    }

    private func captureCandidateFrame() {
        guard isRunning, state == .capturing else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let frame = await self.cameraRepository.singleFrame()

            let evaluatedData = await self.frameQualityRepository.evaluate(frame: frame)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard let sharpData = evaluatedData else {
                    // Could not evaluate – resume monitoring.
                    self.startStabilityMonitoring(); return
                }
                self.handleCandidate(frame: frame, sharpnessData: sharpData)
            }
        }
    }

    /// Evaluates the incoming frame against the current sharp-cell requirement and
    /// decides whether we have accumulated a satisfactory candidate.
    private func handleCandidate(frame: CameraFrame, sharpnessData: FrameSharpnessData) {
        guard isRunning, state == .capturing else { return }

        logSharpnessGrid(sharpnessData)

        if currentMinNumberOfSharpCells == 0.0 {
            let totalCells = sharpnessData.sharpnessGrid.count * sharpnessData.sharpnessGrid.first!.count
            currentMinNumberOfSharpCells = max(1.0, Double(totalCells) / 2.0)
            log("QUALITY: Initialising minSharpCells requirement to half grid → \(String(format: "%.1f", currentMinNumberOfSharpCells))")
        }

        // -----------------------------------------------------------------
        // 1. Use cached sharp-cell counts – no need to rescan the grid.
        // -----------------------------------------------------------------
        var bufferCounts: [Int] = []
        bufferCounts.reserveCapacity(capturedSharpnessFrames.count)
        for item in capturedSharpnessFrames {
            bufferCounts.append(item.data.sharpCellCount)
        }

        let newCount = sharpnessData.sharpCellCount

        // -----------------------------------------------------------------
        // 2. Determine the best frame that meets the current requirement.
        // -----------------------------------------------------------------
        var bestCount = -1
        var bestIndex: Int? = nil // nil → new frame

        for (idx, cnt) in bufferCounts.enumerated() where Double(cnt) >= currentMinNumberOfSharpCells {
            if cnt > bestCount {
                bestCount = cnt
                bestIndex = idx
            }
        }

        if Double(newCount) >= currentMinNumberOfSharpCells && newCount > bestCount {
            bestCount = newCount
            bestIndex = nil
        }

        if Double(bestCount) >= currentMinNumberOfSharpCells {
            let chosenFrame = (bestIndex == nil) ? frame : capturedSharpnessFrames[bestIndex!].frame
            
            _ = transitionTo(.recognizing)

            textRecognizerRepository.processFrame(cameraFrame: chosenFrame, accuracy: .accurate)

            capturedSharpnessFrames.removeAll()
            currentMinNumberOfSharpCells = 0.0

            stabilityObserver?.invalidate(); stabilityObserver = nil
            torchDisposable?.cancel(); torchDisposable = nil
            return
        }

        // -----------------------------------------------------------------
        // 3. No frame passes → update the 3-slot buffer.
        // -----------------------------------------------------------------

        if capturedSharpnessFrames.count < 3 {
            // Buffer not full – append the new failing frame.
            capturedSharpnessFrames.append((frame: frame, data: sharpnessData))
        } else {
            var worstCount = newCount
            var worstIndex: Int? = nil

            for (idx, cnt) in bufferCounts.enumerated() {
                if cnt < worstCount {
                    worstCount = cnt
                    worstIndex = idx
                }
            }

            if let idx = worstIndex {
                capturedSharpnessFrames.remove(at: idx)
                capturedSharpnessFrames.append((frame: frame, data: sharpnessData))
            }
        }

        // -----------------------------------------------------------------
        // 4. Relax the criteria for next attempt
        // -----------------------------------------------------------------
        let newRequirement = max(1.0, currentMinNumberOfSharpCells / minNumberOfSharpCellsReducingFactor)

        log(String(format: "QUALITY: No frame met the requirement (%.1f). Relaxing minSharpCells to %.1f and retrying", currentMinNumberOfSharpCells, newRequirement))
        currentMinNumberOfSharpCells = newRequirement

        if let monitor = stabilityObserver as? CameraStabilityMonitor {
            monitor.clearStableWindow()
        } else {
            startStabilityMonitoring()
        }
    }


    // MARK: - Debug Logging Methods

    func log(_ message: String,
                      level: LogLevel = .debug,
                      category: String = "",
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        // If caller requested a DEBUG-level log and detailed logging is disabled, bail out early.
        if level == .debug && !detailedLoggingEnabled { return }
        logger.log(level, message, category: category, file: file, function: function, line: line)
    }
    
    private func logSentencesDetailed(_ sentences: [Sentence]) {
        guard detailedLoggingEnabled else { return }
        
        log("CENTRAL CLUSTER: Found \(sentences.count) sentences:")
        
        for (index, sentence) in sentences.enumerated() {
            log("  [\(index + 1)] '\(sentence.text)'")
        }
    }
    
    private func logAllRecognizedObservations(_ observations: [TextObservation]) {
        guard detailedLoggingEnabled else { return }
        
        log("RECOGNITION: Found \(observations.count) text observations before filtering:")
        
        for (index, observation) in observations.enumerated() {
            let recognizedText = observation.text
            let confidence = observation.confidence
            
            let boundingBox = observation.boundingBox
            let boxDescription = String(
                format: "box:(%.3f,%.3f,%.3f,%.3f)",
                boundingBox.origin.x, boundingBox.origin.y,
                boundingBox.width, boundingBox.height
            )
            
            log("  [\(index + 1)] '\(recognizedText)' confidence:\(String(format: "%.3f", confidence)) \(boxDescription)")
        }
    }
    
    private func logFilteringResults(originalObservations: [TextObservation], filteredObservations: [TextObservation]) {
        guard detailedLoggingEnabled else { return }
        
        log("CLUSTERING: Filtering results (KEPT vs REMOVED):")
        
        for (index, observation) in originalObservations.enumerated() {
            let recognizedText = observation.text
            let confidence = observation.confidence
            
            let boundingBox = observation.boundingBox
            let boxDescription = String(
                format: "box:(%.3f,%.3f,%.3f,%.3f)",
                boundingBox.origin.x, boundingBox.origin.y,
                boundingBox.width, boundingBox.height
            )
            
            // Check if this observation was kept after filtering
            let wasKept = filteredObservations.contains { filteredObs in
                filteredObs.boundingBox == observation.boundingBox && filteredObs.text == recognizedText
            }
            
            let status = wasKept ? "KEPT" : "REMOVED"
            log("  [\(index + 1)] '\(recognizedText)' confidence:\(String(format: "%.3f", confidence)) \(boxDescription) - \(status)")
        }
    }
    
    
    private func logSharpnessGrid(_ data: FrameSharpnessData) {
        guard detailedLoggingEnabled else { return }
        
        let gridSize = data.sharpnessGrid.count
        var gridVisual = "\n"
        for y in 0..<gridSize {
            var rowStr = ""
            for x in 0..<gridSize {
                let isSharp = data.sharpnessGrid[y][x]
                rowStr += (isSharp ? "▓" : "░")
            }
            gridVisual += rowStr + "\n"
        }
        log(String(format: "SHARPNESS GRID (%d×%d)\n%@", gridSize, gridSize, gridVisual), level: .debug, category: "FRAME_QUALITY")
    }

    /// Visualises the boolean `textGrid` – "▓" for text cells, "░" otherwise.
    private func logTextGrid() {
        guard detailedLoggingEnabled else { return }

        gridQueue.sync {
            guard !textGrid.isEmpty else { return }
            
            let gridSize = textGrid.count
            var gridVisual = ""
            for row in 0..<gridSize {
                for col in 0..<gridSize {
                    let hasText = textGrid[row][col].hasText
                    gridVisual += hasText ? "▓" : "░"
                }
                gridVisual += "\n"
            }
            log(String(format: "TEXT GRID (%d×%d)\n%@", gridSize, gridSize, gridVisual), level: .debug, category: "TEXT_GRID")
        }
    }
}
