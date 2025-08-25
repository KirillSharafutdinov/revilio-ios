//
//  MainViewModel.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import UIKit
import AVFoundation
import Combine

// MARK: - Button State

/// Button states for UI animation
extension MainViewModel {
    enum ButtonState {
        case normal
        case active
        case disabled
    }
}

/// Reactive UI-facing facade for the main screen.
class MainViewModel: ObservableObject {

    // MARK: - Dependencies
    private let searchItemUseCase: SearchItemUseCase
    private let searchTextUseCase: SearchTextUseCase
    private let readTextUseCase: ReadTextUseCase
    private var cameraRepository: CameraRepository
    private var speechSynthesizerRepository: SpeechSynthesizerRepository
    private var objectDetectionRepository: ObjectDetectionRepository
    private var textRecognizerRepository: TextRecognizerRepository
    private let speechRecognizerRepository: SpeechRecognizerRepository
    private(set) var hapticFeedbackRepository: HapticFeedbackRepository
    private let featureCoordinator: FeatureCoordinator
    private let appModeCoordinator: AppModeCoordinating

    // MARK: - Published Properties
    /// State variables
    @Published private(set) var currentMode: AppMode = .idle
    /// Indicates whether the UI should enable the pause / resume toggle.
    @Published private(set) var canPauseResume: Bool = false
    /// Indicates whether any search or reading operation is currently running.
    @Published private(set) var isBusy: Bool = false
    
    // MARK: - Publishers
    /// Emits the latest list of bounding boxes that should be displayed.
    private let boundingBoxesSubject = PassthroughSubject<[BoundingBox], Never>()
    /// Public read-only publisher for bounding boxes.
    var boundingBoxesPublisher: AnyPublisher<[BoundingBox], Never> {
        boundingBoxesSubject.eraseToAnyPublisher()
    }
    
    /// Emits either a bounding box to highlight text or `nil` to hide.
    private let textBoundingBoxSubject = PassthroughSubject<BoundingBox?, Never>()
    var textBoundingBoxPublisher: AnyPublisher<BoundingBox?, Never> {
        textBoundingBoxSubject.eraseToAnyPublisher()
    }
    
    /// Emits the bounding box around the central text cluster in reading mode.
    private let readingClusterQuadSubject = PassthroughSubject<BoundingQuad?, Never>()
    var readingClusterQuadPublisher: AnyPublisher<BoundingQuad?, Never> {
        readingClusterQuadSubject.eraseToAnyPublisher()
    }
    
    /// Publishes UI / developer log lines emitted by the ViewModel & UseCases.
    private let logSubject = PassthroughSubject<String, Never>()
    var logPublisher: AnyPublisher<String, Never> { logSubject.eraseToAnyPublisher() }

    /// Publishes whether the TTS synthesiser is currently speaking.
    var isSpeakingPublisher: AnyPublisher<Bool, Never> {
        if let synth = speechSynthesizerRepository as? AVSpeechSynthesizerService {
            return synth.isSpeakingPublisher
        } else {
            return Just(false).eraseToAnyPublisher()
        }
    }
    
    /// Read-only publisher exposing current application mode
    var currentModePublisher: AnyPublisher<AppMode, Never> {
        $currentMode.eraseToAnyPublisher()
    }
    
    /// Exposes the current zoom preset name (forwarded from `AppModeCoordinator`).
    var zoomNamePublisher: AnyPublisher<String, Never> {
        appModeCoordinator.zoomNamePublisher
    }
    
    /// Exposes the per-mode button states (forwarded from `AppModeCoordinator`).
    var buttonStatesPublisher: AnyPublisher<[AppMode: ButtonState], Never> {
        appModeCoordinator.buttonStatesPublisher
    }

    /// Exposes the secondary control button states.
    var secondaryButtonStatesPublisher: AnyPublisher<[SecondaryButton: ButtonState], Never> {
        appModeCoordinator.secondaryButtonStatesPublisher
    }

    /// One-off event signalling that UI overlays should be cleared (forwarded).
    var uiClearPublisher: AnyPublisher<Void, Never> {
        appModeCoordinator.uiClearPublisher
    }
    
    private let searchItemNameSubject = PassthroughSubject<String?, Never>()
    var searchItemNamePublisher: AnyPublisher<String?, Never> {
        searchItemNameSubject.eraseToAnyPublisher()
    }
    
    private let searchTextQuerySubject = PassthroughSubject<String?, Never>()
    var searchTextQueryPublisher: AnyPublisher<String?, Never> {
        searchTextQuerySubject.eraseToAnyPublisher()
    }
    /// Publishes whether the Previous/Next navigation buttons should be enabled in the UI.
    /// True when the app is in `.readingText` mode and the ReadTextUseCase has recognised
    /// at least one sentence that can be navigated.
    var readingNavigationEnabledPublisher: AnyPublisher<Bool, Never> {
        readTextUseCase.navigationEnabledPublisher
            .combineLatest(currentModePublisher)
            .map { hasText, mode in
                return hasText && mode == .readingText
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Emits pause / resume events from reading, item search, and text search modes.
    private let readingPauseSubject = PassthroughSubject<Bool, Never>()
    var readingPausePublisher: AnyPublisher<Bool, Never> {
        readingPauseSubject.eraseToAnyPublisher()
    }

    /// Emits once when the camera scene stabilises (forwarded from ReadTextUseCase)
    var cameraStablePublisher: AnyPublisher<Void, Never> {
        readTextUseCase.sceneStablePublisher
    }
    
    private let voiceOverStatusSubject = CurrentValueSubject<Bool, Never>(UIAccessibility.isVoiceOverRunning)
    var voiceOverStatusPublisher: AnyPublisher<Bool, Never> {
        voiceOverStatusSubject.eraseToAnyPublisher()
    }
    
    // Automatic cancellable storage
    private var cancellables = OperationBag()
    
    // MARK: - Initialization
    
    init(
        searchItemUseCase: SearchItemUseCase,
        searchTextUseCase: SearchTextUseCase,
        readTextUseCase: ReadTextUseCase,
        cameraRepository: CameraRepository,
        speechSynthesizerRepository: SpeechSynthesizerRepository,
        objectDetectionRepository: ObjectDetectionRepository,
        textRecognizerRepository: TextRecognizerRepository,
        speechRecognizerRepository: SpeechRecognizerRepository,
        hapticFeedbackRepository: HapticFeedbackRepository,
        appModeCoordinator: AppModeCoordinating
    ) {
        self.searchItemUseCase = searchItemUseCase
        self.searchTextUseCase = searchTextUseCase
        self.readTextUseCase = readTextUseCase
        self.cameraRepository = cameraRepository
        self.speechSynthesizerRepository = speechSynthesizerRepository
        self.objectDetectionRepository = objectDetectionRepository
        self.textRecognizerRepository = textRecognizerRepository
        self.speechRecognizerRepository = speechRecognizerRepository
        self.hapticFeedbackRepository = hapticFeedbackRepository
        self.appModeCoordinator = appModeCoordinator
        
        self.featureCoordinator = FeatureCoordinator(
            searchItemUseCase: searchItemUseCase,
            searchTextUseCase: searchTextUseCase,
            readTextUseCase: readTextUseCase,
            appModeCoordinator: appModeCoordinator
        )
        
        bindPublishers()
    }
    
    // MARK: - Camera Management

    /// Starts the camera and prepares the preview layer using a **Combine-first** API.
    /// - Parameter view: The UIView that should host the live preview.
    /// - Returns: A publisher that emits `true` on success or `false` on failure and then completes.
    func startCameraPublisher(in view: UIView) -> AnyPublisher<Bool, Never> {
        cameraRepository
            .setUp(preset: .photo)
            .receive(on: RunLoop.main)
            .handleEvents(receiveOutput: { [weak self, weak view] success in
                guard let self = self, let hostView = view, success else { return }
                // Attach preview layer
                if let previewLayer = self.cameraRepository.previewLayer {
                    previewLayer.frame = hostView.bounds
                    hostView.layer.addSublayer(previewLayer)
                }
                // Start the capture session
                self.cameraRepository.start()
                // Apply initial zoom preset without feedback (on launch)
                self.appModeCoordinator.applyCurrentZoom()
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Feature Control

    /// Start item search function
    func startSearchItem() {
        featureCoordinator.didTapSearchItem()
        provideButtonFeedback()
    }
    
    /// Stop current search for list input (called when button is pressed with list input method)
    func stopCurrentSearchForListInput() {
        appModeCoordinator.immediateTermination()
        // Schedule haptic feedback slightly after the immediate termination so that any
        // internal `haptics.stop()` calls complete first, preventing our pattern from
        // being cancelled prematurely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.provideButtonFeedback()
        }
    }
    
    /// Start item search with a preselected item from list (bypasses voice recognition)
    /// - Parameters:
    ///   - itemName: The class name of the item in the ML model
    ///   - modelName: The name of the ML model to use
    func startSearchItemFromList(itemName: String, modelName: String) {
        provideButtonFeedback()
        appModeCoordinator.activate(.searchingItem, shouldTerminate: true, zoomIndex: -1)
        
        guard currentMode == .searchingItem else { return }

        searchItemUseCase.startItemSearchWithPreselectedItem(itemName: itemName, modelName: modelName)
    }
    
    /// Start text search function
    func startSearchText() {
        if let soundURL = Bundle.main.url(forResource: "startTextSearch", withExtension: "aac") {
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        }
        featureCoordinator.didTapSearchText()
        provideButtonFeedback()
    }
    
    /// Start text search with keyboard input (bypasses voice recognition)
    /// - Parameter text: The text entered via keyboard
    func startSearchTextWithKeyboard(text: String) {
        provideButtonFeedback()
        appModeCoordinator.activate(.searchingText, shouldTerminate: true, zoomIndex: -1)
        
        guard currentMode == .searchingText else { return }
        searchTextUseCase.startTextSearchWithPreenteredText(text)
    }
    
    /// Start text reading function
    func startReadText() {
        provideButtonFeedback()
        featureCoordinator.didTapReadText()
        provideButtonFeedback()
    }
    
    /// Stop current function
    func stopCurrentTask() {
        appModeCoordinator.resetZoomToDefault()
        StopController.shared.stopAll(reason: .user)
        appModeCoordinator.resetStateKeepingZoom()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.provideButtonFeedback()
        }
    }
    
    // MARK: - Input Methods

    /// Get the current item input method from settings
    /// - Returns: The current item input method (voice or list)
    func getItemInputMethod() -> ItemInputMethod {
        let defaults = UserDefaults.standard
        let index = defaults.object(forKey: "settings.itemInputMethod") as? Int ?? ItemInputMethod.voice.rawValue
        return ItemInputMethod(rawValue: index) ?? .voice
    }
    
    /// Get the current text input method from settings
    /// - Returns: The current text input method (voice or keyboard)
    func getTextInputMethod() -> TextInputMethod {
        let defaults = UserDefaults.standard
        let index = defaults.object(forKey: "settings.textInputMethod") as? Int ?? TextInputMethod.voice.rawValue
        return TextInputMethod(rawValue: index) ?? .voice
    }
    
    // MARK: - Reading Controls
    
    /// Go to next text block when reading
    func nextTextBlock() {
        if currentMode == .readingText {
            // Provide haptic feedback for navigation
            provideButtonFeedback()
            // Use the dedicated method for speech interruption and navigation
            readTextUseCase.speakNextBlock()
        }
    }
    
    /// Go to previous text block when reading
    func previousTextBlock() {
        if currentMode == .readingText {
            // Provide haptic feedback for navigation
            provideButtonFeedback()
            // Use the dedicated method for speech interruption and navigation
            readTextUseCase.speakPreviousBlock()
        }
    }
    
    // MARK: - Pause/Resume Controls
    
    /// Indicates whether *any* active task (reading, item search or text search) is paused.
    /// Allows the Presentation layer to update UI consistently across all modes.
    func isCurrentTaskPaused() -> Bool {
        return readTextUseCase.isPaused || searchItemUseCase.isPaused || searchTextUseCase.isPaused
    }

    /// Toggles pause / resume state for the *current active* session (reading, item search, text search).
    /// - Returns: `true` if the session is now paused, `false` if it has resumed or pausing is not applicable.
    @discardableResult
    func togglePauseResumeCurrentTask() -> Bool {
        switch currentMode {
        case .readingText:
            return togglePauseResumeReading()
        case .searchingItem:
            return togglePauseResumeItemSearch()
        case .searchingText:
            return togglePauseResumeTextSearch()
        case .idle:
            return false
        }
    }

    // MARK: - Zoom Controls

    /// Decrease camera zoom and announce the new zoom preset name.
    func decreaseZoom() -> String {
        return appModeCoordinator.decreaseZoom()
    }

    /// Increase camera zoom and announce the new zoom preset name.
    func increaseZoom() -> String {
        return appModeCoordinator.increaseZoom()
    }

    // MARK: - Audio Management

    /// Toggles reading speed between normal and accelerated presets.
    func changeReadingSpeed() {
        speechSynthesizerRepository.toggleReadingSpeed()
        let currentSpeed = speechSynthesizerRepository.readingSpeed

        let hapticPattern: HapticPattern = currentSpeed == .normal ? .dashDotPause : .dotDashPause
        hapticFeedbackRepository.playPattern(hapticPattern, intensity: Constants.hapticButtonIntensity)
    }

    /// Returns the current audio output route (built-in, headphones, etc.).
    func getCurrentAudioOutputRoute() -> AudioOutputRoute {
        return speechSynthesizerRepository.audioOutputRoute
    }
    
    /// VoiceOver features management
    func voiceOverStatusChanged(_ isVoiceOverRunning: Bool) {
        readTextUseCase.isVoiceOverRunning = isVoiceOverRunning
    }
    
    // MARK: - Button State Management

    /// Convenience helper that fetches the three primary button states in one call.
    func getButtonStates() -> (searchItem: ButtonState, searchText: ButtonState, readText: ButtonState) {
        return (
            appModeCoordinator.buttonState(for: .searchingItem),
            appModeCoordinator.buttonState(for: .searchingText),
            appModeCoordinator.buttonState(for: .readingText)
        )
    }

    // MARK: - Haptic Feedback Helpers

    func provideButtonFeedback() {
        hapticFeedbackRepository.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
    }

    func provideSuccessFeedback() {
        hapticFeedbackRepository.playPattern(.dotDashPause, intensity: Constants.hapticSuccessIntensity)
    }

    func provideErrorFeedback() {
        hapticFeedbackRepository.playPattern(.dashDotPause, intensity: Constants.hapticErrorIntensity)
    }

    func stopHapticFeedback() {
        hapticFeedbackRepository.stop()
    }

    // MARK: - Model Management

    /// Pre-warms the default object-detection model on a background queue so that it is ready
    /// by the time the user scrolls through the item list.
    func prewarmDefaultObjectDetectionModel() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.objectDetectionRepository.initialize(modelName: "yolo11mCOCO")
        }
    }
    
    // MARK: - Private UI Helpers
    
    private func bindPublishers() {
        self.appModeCoordinator.currentModePublisher
             .sink { [weak self] mode in
                 guard let self else { return }
                 self.currentMode = mode
             }
             .store(in: &cancellables)

        self.appModeCoordinator.uiClearPublisher
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.boundingBoxesSubject.send([])
                    self.textBoundingBoxSubject.send(nil)
                    self.readingClusterQuadSubject.send(nil)
                }
            }
            .store(in: &cancellables)

        // ===== Search-state streams → simple UI flags/logs =====
        self.featureCoordinator.isBusyPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] busy in
                self?.isBusy = busy
            }
            .store(in: &cancellables)

        self.featureCoordinator.processingStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if case .error(let msg?) = state {
                    self?.logSubject.send("Search error: \(msg)")
                }
            }
            .store(in: &cancellables)
        
        // Pause / resume events from coordinator
        self.featureCoordinator.pauseStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] paused in
                self?.readingPauseSubject.send(paused)
                if paused {
                    // Clear overlays when paused
                    self?.boundingBoxesSubject.send([])
                    self?.textBoundingBoxSubject.send(nil)
                }
            }
            .store(in: &cancellables)

        // Use case activity determines pausability
        self.featureCoordinator.isAnyUseCaseActivePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isAnyActive in
                // Can pause/resume when any use case is in an active state
                self?.canPauseResume = isAnyActive
            }
            .store(in: &cancellables)
        
        // ===== Speech recognition transcripts → log stream  =====
        self.speechRecognizerRepository
            .transcriptPublisher()
            .sink(receiveCompletion: { completion in
                if case .failure(_) = completion {
                }
            }, receiveValue: { [weak self] text in
                self?.logSubject.send("STT: \(text)")
            })
            .store(in: &cancellables)

        // ===== Camera stability → UI haptic hint =====
        self.readTextUseCase.sceneStablePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // Provide a subtle haptic cue indicating camera is stable.
                self?.hapticFeedbackRepository.playPattern(.dotPause, intensity: 0.4)
            }
            .store(in: &cancellables)

        // Text recognition observations → search or reading handlers
        self.textRecognizerRepository.recognizedTextPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] observations in
                guard let self = self else { return }
                switch self.currentMode {
                case .searchingText:
                    self.handleTextObservationsForSearchUI(observations: observations)
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Central cluster rectangle updates → overlay (reading mode)
        self.readTextUseCase.centralClusterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] quad in
                guard let self else { return }
                // Forward only when in reading mode
                if self.currentMode == .readingText {
                    if let q = quad {
                        self.readingClusterQuadSubject.send(q)
                    } else {
                        self.readingClusterQuadSubject.send(nil)
                    }
                } else {
                    // When leaving reading mode, hide overlay.
                    self.readingClusterQuadSubject.send(nil)
                }
            }
            .store(in: &cancellables)
        
        // Object detection results → bounding box overlay
        self.objectDetectionRepository.detectionsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detections in
                self?.handleObjectDetectionsForUI(detections: detections)
            }
            .store(in: &cancellables)
        
        self.searchItemUseCase.currentSearchTargetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] itemName in
                guard let self else { return }
                if self.currentMode == .searchingItem {
                    if let itemName = itemName {
                        self.searchItemNameSubject.send(itemName)
                    } else {
                        self.searchItemNameSubject.send(nil)
                    }
                } else {
                    // When leaving search item mode, hide overlay.
                    self.searchItemNameSubject.send(nil)
                }
            }
            .store(in: &cancellables)
        
        self.searchTextUseCase.currentSearchQueryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] textQuery in
                guard let self else { return }
                if self.currentMode == .searchingText {
                    if let textQuery = textQuery {
                        self.searchTextQuerySubject.send(textQuery)
                    } else {
                        self.searchTextQuerySubject.send(nil)
                    }
                } else {
                    // When leaving search item mode, hide overlay.
                    self.searchTextQuerySubject.send(nil)
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
                    .map { _ in UIAccessibility.isVoiceOverRunning }
                    .sink { [weak self] isRunning in
                        self?.handleVoiceOverStatusChange(isRunning: isRunning)
                    }
                    .store(in: &cancellables)
    }
    
    private func handleVoiceOverStatusChange(isRunning: Bool) {
        voiceOverStatusSubject.send(isRunning)
        
        readTextUseCase.isVoiceOverRunning = isRunning
        searchTextUseCase.isVoiceOverRunning = isRunning
        searchItemUseCase.isVoiceOverRunning = isRunning
    }
    
    private func convertToUIBoundingBoxes(from observations: [ObjectObservation]) -> [BoundingBox] {
        return observations.map { observation in
            BoundingBox(
                rect: observation.boundingBox,
                label: "\(ItemsForSearchRegistryService.shared.localizedName(forClassName: observation.label)) \(Int(min(observation.confidence * 100, 100)))%",
                confidence: observation.confidence
            )
        }
    }

    /// Finds the recognised text observation that best matches the current search query.
    private func findMatchingTextObservation(in observations: [TextObservation]) -> TextObservation? {
        let searchQuery = searchTextUseCase.currentSearchQuery?.lowercased() ?? ""
        guard !searchQuery.isEmpty else { return nil }

        let matching = observations.filter { $0.text.lowercased().contains(searchQuery) }
        guard !matching.isEmpty else { return nil }

        if matching.count == 1 { return matching[0] }

        // Pick the one closest to the screen centre.
        let centre = CGPoint(x: 0.5, y: 0.5)
        return matching.min { lhs, rhs in
            let d1 = hypot(lhs.boundingBox.midX - centre.x, lhs.boundingBox.midY - centre.y)
            let d2 = hypot(rhs.boundingBox.midX - centre.x, rhs.boundingBox.midY - centre.y)
            return d1 < d2
        }
    }

    /// Returns the bounding rectangle of the specific substring match closest to the text box centre.
    private func highlightBoundingBox(for searchQuery: String, in observation: TextObservation) -> CGRect {
        let candidate = observation.text.lowercased()
        let query     = searchQuery.lowercased()
        guard let _ = candidate.range(of: query) else { return observation.boundingBox }

        let ranges = candidate.ranges(of: query)
        guard !ranges.isEmpty else { return observation.boundingBox }

        let total = CGFloat(candidate.count)
        let obsBox = observation.boundingBox
        let obsMid = obsBox.midX

        var bestRect = obsBox
        var minDist  = CGFloat.greatestFiniteMagnitude

        for r in ranges {
            let lower = CGFloat(candidate.distance(from: candidate.startIndex, to: r.lowerBound))
            let upper = CGFloat(candidate.distance(from: candidate.startIndex, to: r.upperBound))

            let startX = obsBox.minX + (lower / total) * obsBox.width
            let endX   = obsBox.minX + (upper / total) * obsBox.width
            let width  = max(endX - startX, 0.0001)
            let rect   = CGRect(x: startX, y: obsBox.minY, width: width, height: obsBox.height)

            let centreX = (startX + endX) / 2.0
            let dist = abs(centreX - obsMid)
            if dist < minDist {
                minDist = dist; bestRect = rect
            }
        }
        return bestRect
    }

    // MARK: - UI Update Handlers
    
    /// Updates the bounding-box overlay for object-detection results.
    private func handleObjectDetectionsForUI(detections: [ObjectObservation]) {
        guard currentMode == .searchingItem else { return }

        let boxes = convertToUIBoundingBoxes(from: detections)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.currentMode == .searchingItem else { return }
            self.boundingBoxesSubject.send(boxes)
        }
    }

    /// Highlights the portion of recognised text that matches the current search query.
    private func handleTextObservationsForSearchUI(observations: [TextObservation]) {
        guard currentMode == .searchingText else { return }

        // When there are no observations, clear overlay and exit.
        guard !observations.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.currentMode == .searchingText else { return }
                self.textBoundingBoxSubject.send(nil)
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard self.currentMode == .searchingText else { return }

            if let matching = self.findMatchingTextObservation(in: observations) {
                let query = self.searchTextUseCase.currentSearchQuery?.lowercased() ?? ""
                let rect  = self.highlightBoundingBox(for: query, in: matching)
                let box   = BoundingBox(rect: rect, label: "«\(query)»", confidence: matching.confidence)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.currentMode == .searchingText else { return }
                    self.textBoundingBoxSubject.send(box)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.currentMode == .searchingText else { return }
                    self.textBoundingBoxSubject.send(nil)
                }
            }
        }
    }

    // MARK: - Pause/Resume Helpers

    private func togglePauseResumeItemSearch() -> Bool {
        guard currentMode == .searchingItem else { return false }

        if searchItemUseCase.isPaused {
            provideButtonFeedback()
            searchItemUseCase.resume()
            return false
        } else {
            provideButtonFeedback()
            searchItemUseCase.pause()
            return true
        }
    }

    private func togglePauseResumeTextSearch() -> Bool {
        guard currentMode == .searchingText else { return false }

        if searchTextUseCase.isPaused {
            provideButtonFeedback()
            searchTextUseCase.resume()
            return false
        } else {
            provideButtonFeedback()
            searchTextUseCase.pause()
            return true
        }
    }

    @discardableResult
    private func togglePauseResumeReading() -> Bool {
        guard currentMode == .readingText else { return false }

        if readTextUseCase.isPaused {
            provideButtonFeedback()
            readTextUseCase.resume()
            return false
        } else {
            provideButtonFeedback()
            readTextUseCase.pause()
            return true
        }
    }
}
