//
//  MainViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Vision
import Speech
import AVFoundation
import Combine

protocol ModalDismissDelegate: AnyObject {
    func modalDidDismiss()
}

/// Serves as the main application controller, managing the primary user interface and
/// coordinating text reading, object search, and text search functionalities. Handles
/// camera display, bounding box visualization, and user interaction across all major
/// application features through a comprehensive state management system.
class MainViewController: BaseViewController {
    
    // MARK: - Outlets
    
    @IBOutlet weak var readTextButton: UIButton!
    @IBOutlet weak var searchItemButton: UIButton!
    @IBOutlet weak var searchTextButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton?
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var forwardButton: UIButton!
    @IBOutlet weak var zoomMinusButton: UIButton!
    @IBOutlet weak var zoomPlusButton: UIButton!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var tutorialButton: UIButton!
    @IBOutlet weak var toggleReadingSpeedButton: UIButton?
    @IBOutlet var videoPreview: UIView!
    @IBOutlet weak var searchObjectLabel: UILabel!
    
    // MARK: - Properties
    
    private var viewModel: MainViewModel!
    private var boundingBoxViews: [BoundingBoxView] = []
    private let maxBoundingBoxViews = 100
    private var colors: [String: UIColor] = [:]
    private let clusterQuadView = QuadView()
    
    private let cameraReadyIndicator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .systemGreen
        v.layer.cornerRadius = 6
        v.alpha = 0.0
        return v
    }()

    private var isTrainingButtonEnabled: Bool {
        return SettingsManager.shared.trainingMenuEnabled
    }
        
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.usesAdaptiveButtonBackground = false
        
        searchObjectLabel.layer.cornerRadius = 10
        searchObjectLabel.layer.masksToBounds = true
        searchObjectLabel.textColor = .white
        searchObjectLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        setupBoundingBoxViews()
        setupCameraReadyIndicator()
        
        requestCameraPermissions()
        requestMicrophonePermissions()
        
        updateTrainingButtonState()

        if let ppButton = playPauseButton {
            viewModel.$canPauseResume
                .receive(on: RunLoop.main)
                .assign(to: \UIButton.isEnabled, on: ppButton)
                .store(in: &bag)
        }
        
        viewModel.readingNavigationEnabledPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                let alpha: CGFloat = enabled ? 1.0 : 0.4
                self.backButton?.isEnabled = enabled
                self.forwardButton?.isEnabled = enabled
                self.backButton?.alpha = alpha
                self.forwardButton?.alpha = alpha
            }
            .store(in: &bag)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupAccessibility()
        updateTexts()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        announceMainScreen()
    }
    
    // MARK: - Public Methods

    /// Set the view model from outside (e.g., AppCoordinator or Dependency Container)
    func setViewModel(_ viewModel: MainViewModel) {
        self.viewModel = viewModel
        bindPublishers()
    }
    
    // MARK: - Actions
    
    @IBAction func searchItemButtonTap(_ sender: Any) {
        let inputMethod = viewModel.getItemInputMethod()
        
        switch inputMethod {
        case .voice:
            viewModel.startSearchItem()
        case .list:
            viewModel.stopCurrentSearchForListInput()
            presentItemListSelector()
        }
    }
    
    @IBAction func searchTextButtonTap(_ sender: Any) {
        let inputMethod = viewModel.getTextInputMethod()
        
        switch inputMethod {
        case .voice:
            viewModel.startSearchText()
        case .keyboard:
            viewModel.stopCurrentTask()
            presentTextInputController()
        }
    }
    
    @IBAction func readTextButtonTap(_ sender: Any) {
        viewModel.startReadText()
    }
    
    /// IBAction connected to the playPauseButton to toggle pause / resume during text reading.
    @IBAction func playPauseButtonTap(_ sender: Any) {
        viewModel.togglePauseResumeCurrentTask()

        let newTitle: String = (viewModel?.isCurrentTaskPaused() ?? false) // TODO
            ? R.string.main.resume()
            : R.string.main.pause()
        if let button = sender as? UIButton {
            if var configuration = button.configuration {
                configuration.title = newTitle
                button.configuration = configuration
            } else {
                button.setTitle(newTitle, for: .normal)
            }
        }
    }
    
    @IBAction func stopButtonTap(_ sender: Any) {
        viewModel.stopCurrentTask()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.announceMainScreen()
        }
    }
    
    @IBAction func backButtonTap(_ sender: Any) {
        viewModel.previousTextBlock()
    }
    
    @IBAction func nextButtonTap(_ sender: Any) {
        viewModel.nextTextBlock()
    }
    
    @IBAction func changeReadingSpeedButtonTap(_ sender: Any) {
        viewModel.changeReadingSpeed()
    }
    
    @IBAction func zoomMinusButtonTap(_ sender: Any) {
        _ = viewModel.decreaseZoom()
    }
    
    @IBAction func zoomPlusButtonTap(_ sender: Any) {
        _ = viewModel.increaseZoom()
    }
    
    /// Presents the settings menu modally.
    @IBAction func settingsButtonTap(_ sender: Any) {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)

        if let nav = presentedViewController as? UINavigationController,
           nav.topViewController is SettingsViewController {
            nav.dismiss(animated: true)
            return
        }

        if let currentModal = presentedViewController {
            currentModal.dismiss(animated: false) { [weak self] in
                self?.presentSettings()
            }
            return
        }

        presentSettings()
    }
    
    /// Launches the in-app tutorial / training flow.
    @IBAction func tutorialButtonTap(_ sender: Any) {
        guard isTrainingButtonEnabled else { return }
        
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)

        if presentedViewController is TrainingViewController {
            return
        }

        if let currentModal = presentedViewController {
            currentModal.dismiss(animated: false) { [weak self] in
                self?.presentTraining()
            }
            return
        }

        presentTraining()
    }
    
    @IBAction func pinch(_ pinch: UIPinchGestureRecognizer) {
        // TODO Pinch to zoom functionality can be added here if needed
    }
    
    // MARK: - Setup
    
    private func setupBoundingBoxViews() {
        for _ in 0..<maxBoundingBoxViews {
            let boxView = BoundingBoxView()
            boundingBoxViews.append(boxView)
        }
        
        let itemDisplayInfoList = ItemsForSearchRegistryService.shared.getAllAvailableItemsForDisplay()
        
        // Assign colors to each class
        for itemDisplayInfo in itemDisplayInfoList {
            colors[itemDisplayInfo.displayName] = UIColor(
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 0.6
            )
        }
    }
    
    private func setupCameraReadyIndicator() {
        view.addSubview(cameraReadyIndicator)
        NSLayoutConstraint.activate([
            cameraReadyIndicator.widthAnchor.constraint(equalToConstant: 12),
            cameraReadyIndicator.heightAnchor.constraint(equalToConstant: 12),
            cameraReadyIndicator.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            cameraReadyIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
    }
    
    // MARK: - UI Updates
    
    /// Updates all visible texts so they reflect the current `AppLanguage`.
    internal override func updateTexts() {
        if let button = tutorialButton {
            setButtonTitle(button, title: R.string.main.tutorial())
        }
        
        if let button = settingsButton {
            setButtonTitle(button, title: R.string.main.settings())
        }
        
        if let button = searchItemButton {
            setButtonTitle(button, title: R.string.main.searchItem())
        }
        
        if let button = readTextButton {
            setButtonTitle(button, title: R.string.main.readText())
        }
        
        if let button = searchTextButton {
            setButtonTitle(button, title: R.string.main.searchText())
        }
        
        if let button = backButton {
            setButtonTitle(button, title: R.string.main.back())
        }
        
        if let button = forwardButton {
            setButtonTitle(button, title: R.string.main.forward())
        }
        
        if let button = stopButton {
            setButtonTitle(button, title: R.string.main.stop())
        }
        
        if let button = zoomMinusButton {
            setButtonTitle(button, title: R.string.main.zoomOut())
        }
        
        if let button = zoomPlusButton {
            setButtonTitle(button, title: R.string.main.zoomIn())
        }
        
        if let button = playPauseButton {
            let newTitle = (viewModel?.isCurrentTaskPaused() ?? false)
                ? R.string.main.resume()
                : R.string.main.pause()
            setButtonTitle(button, title: newTitle)
        }
        
        if let button = toggleReadingSpeedButton {
            setButtonTitle(button, title: R.string.main.toggleReadingSpeed())
        }
        
        setupBoundingBoxViews()
    }
    
    internal override func setupAccessibility() {
        backButton?.accessibilityTraits = .none
        forwardButton?.accessibilityTraits = .none
        playPauseButton?.accessibilityTraits = .none
        
        tutorialButton?.accessibilityTraits = .none
        settingsButton?.accessibilityTraits = .none
        searchItemButton?.accessibilityTraits = .none
        readTextButton?.accessibilityTraits = .none
        searchTextButton?.accessibilityTraits = .none
        stopButton?.accessibilityTraits = .none
        zoomMinusButton?.accessibilityTraits = .none
        zoomPlusButton?.accessibilityTraits = .none
        toggleReadingSpeedButton?.accessibilityTraits = .none
    }

    private func updatePlayPauseButtonTitle(paused: Bool) {
        guard let button = self.playPauseButton else { return }
        let newTitle = paused ? R.string.main.resume() : R.string.main.pause()
        if var configuration = button.configuration {
            configuration.title = newTitle
            button.configuration = configuration
        } else {
            button.setTitle(newTitle, for: .normal)
        }
    }
    
    private func updateTrainingButtonState() {
        guard let button = tutorialButton else { return }
        let enabled = isTrainingButtonEnabled
        button.isEnabled = enabled
        button.alpha = enabled ? 1.0 : 0.4
        button.accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }
    
    private func updateSearchLabel(for currentMode: AppMode?, value: String?) {
        guard let value = value, let currentMode = currentMode else {
            UIView.animate(withDuration: 0.3) {
                self.searchObjectLabel.text = ""
                self.searchObjectLabel.alpha = 0
            }
            return
        }
        
        switch currentMode {
        case .searchingItem:
            let localized = ItemsForSearchRegistryService.shared.localizedName(forClassName: value)
            searchObjectLabel.text = "\(Constants.SearchItem.announcementPrefix) \(localized.uppercased())"
            UIView.animate(withDuration: 0.3) {
                self.searchObjectLabel.alpha = 1
            }
        case .searchingText:
            searchObjectLabel.text = "\(Constants.SearchText.announcementPrefix) \(value.uppercased())"
            UIView.animate(withDuration: 0.3) {
                self.searchObjectLabel.alpha = 1
            }
        default:
            UIView.animate(withDuration: 0.3) {
                self.searchObjectLabel.text = ""
                self.searchObjectLabel.alpha = 0
            }
        }
    }
    
    private func showBoundingBoxes(_ boxes: [BoundingBox]) {
        for i in 0..<boundingBoxViews.count {
            if i < boxes.count {
                let box = boxes[i]
                let color = colors[box.label.components(separatedBy: " ").first ?? ""] ?? UIColor.white
                boundingBoxViews[i].show(
                    frame: convertNormalizedRect(box.rect, to: videoPreview.bounds),
                    label: box.label,
                    color: color,
                    alpha: CGFloat((box.confidence - 0.2) / (1.0 - 0.2) * 0.9)
                )
            } else {
                boundingBoxViews[i].hide()
            }
        }
    }
    
    private func showTextBoundingBox(_ box: BoundingBox) {
        let convertedRect = convertNormalizedRect(box.rect, to: videoPreview.bounds)
        boundingBoxViews[0].show(
            frame: convertedRect,
            label: "Text in scope",
            color: UIColor.green,
            alpha: 0.5
        )
        
        // Hide other boxes
        for i in 1..<boundingBoxViews.count {
            boundingBoxViews[i].hide()
        }
    }
    
    private func showCentralClusterQuad(_ quad: BoundingQuad) {
        clusterQuadView.show(
            quad: quad,
            color: UIColor.yellow,
            alpha: 0.6,
            in: videoPreview.bounds,
            transform: convertNormalizedPoint(_:to:)
        )
    }
    
    // MARK: - Camera & Permissions
    
    private func startCamera() {
        viewModel.startCameraPublisher(in: videoPreview)
            .receive(on: RunLoop.main)
            .sink { [weak self] success in
                guard let self = self else { return }
                if success {
                    for box in self.boundingBoxViews {
                        box.addToLayer(self.videoPreview.layer)
                    }
                    self.clusterQuadView.addToLayer(self.videoPreview.layer)
                } else {
                    self.showAlert(title: "Error", message: "Failed to start camera")
                }
            }
            .store(in: &bag)
    }
    
    private func requestCameraPermissions() {
        // Check current camera permission status
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch cameraAuthStatus {
        case .authorized:
            // Camera permission already granted, check speech recognition
            startCamera()
        case .notDetermined:
            // Request camera permission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startCamera()
                    } else {
                        self?.showAlert(title: "Permission Denied", message: "Camera permission was declined")
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(title: "Permission Denied", message: "Camera permission was declined")
            }
        @unknown default:
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(title: "Permission Error", message: "Unknown camera permission status")
            }
        }
    }
    
    private func requestMicrophonePermissions() {
        let micStatus = AVAudioSession.sharedInstance().recordPermission
        switch micStatus {
        case .granted:
            DispatchQueue.main.async { [weak self] in
                self?.requestSpeechRecognizerPermissions()
            }
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] status in
                DispatchQueue.main.async {
                    if status == true {
                        self?.requestSpeechRecognizerPermissions()
                    } else {
                        self?.showAlert(title: "Permission Denied", message: "Microfone permission was declined")
                    }
                }
            }
        case .denied:
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(title: "Permission Denied", message: "Microfone permission was declined")
            }
        @unknown default:
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(title: "Permission Error", message: "Unknown microfone permission status")
            }
        }
    }
    
    private func requestSpeechRecognizerPermissions() {
        let speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
        
        switch speechAuthStatus {
        case .authorized:
            announceMainScreen()
        case .notDetermined:
            // Request speech recognition permission
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        self?.announceMainScreen()
                    } else {
                        self?.showAlert(title: "Permission Denied", message: "Speech recognition permission was declined")
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(title: "Permission Denied", message: "Speech recognition permission was declined")
            }
        @unknown default:
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(title: "Permission Error", message: "Unknown speech recognition permission status")
            }
        }
    }
    
    // MARK: - Presentation

    private func presentSettings() {
        let storyboard = UIStoryboard(name: "Settings", bundle: nil)

        guard let settingsVC = storyboard.instantiateInitialViewController() as? SettingsContainerViewController else {
            assertionFailure("Unable to instantiate initial view controller from Settings.storyboard")
            return
        }
        
        settingsVC.modalDismissDelegate = self
        settingsVC.modalPresentationStyle = .overFullScreen
        present(settingsVC, animated: true)
    }

    /// Helper to create and present the training screen.
    private func presentTraining() {
        let trainingVC = TrainingViewController()
        
        trainingVC.modalDismissDelegate = self
        trainingVC.modalPresentationStyle = .overFullScreen
        present(trainingVC, animated: true)
    }
    
    private func presentItemListSelector() {
        // Kick off an asynchronous warm-up of the default object-detection model so it is ready while the
        // user scrolls through the list. The method is idempotent – if the model is already cached the
        // call returns quickly with no extra work.
        viewModel.prewarmDefaultObjectDetectionModel()

        let itemListVC = ItemListViewController()
        
        itemListVC.delegate = self
        itemListVC.modalPresentationStyle = .overFullScreen

        present(itemListVC, animated: true)
    }
        
    private func presentTextInputController() {
        if presentedViewController != nil {
            dismiss(animated: false) { [weak self] in
                self?.presentTextInputController()
            }
            return
        }
        
        let textInputViewController = TextInputViewController()
        
        textInputViewController.delegate = self
        textInputViewController.modalPresentationStyle = .overFullScreen
        
        present(textInputViewController, animated: true)
    }
    
    private func showCameraReadyIndicator() {
        cameraReadyIndicator.alpha = 0.0
        UIView.animate(withDuration: 0.3, animations: {
            self.cameraReadyIndicator.alpha = 1.0
        }) { _ in
            // Hide after 1.5s
            UIView.animate(withDuration: 0.6, delay: 1.5, options: [], animations: {
                self.cameraReadyIndicator.alpha = 0.0
            }, completion: nil)
        }
    }
    
    // MARK: - Helpers
    
    private func announceMainScreen() {
        guard !speechSynthesizer.isSpeaking else { return }
        
        if viewModel.currentMode == .idle {
            announce(text: R.string.main.idleAnnouncement())
        }
    }
    
    /// Converts Vision normalized rectangle (0–1 coordinate space, origin bottom-left) to UIKit rect in the given bounds, accounting for 4:3 camera aspectFill cropping.
    private func convertNormalizedRect(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = bounds.width
        let height = bounds.height

        // Calculate aspect ratio correction factor (capture 4:3 vs screen aspect)
        let ratio = (height / width) / (4.0 / 3.0)
        let scale = 1.0 / ratio
        let offsetX = (1.0 - scale) / 2.0

        // Adjust X coordinates for the horizontal crop applied by .aspectFill
        let adjustedX = (rect.origin.x - offsetX) / scale
        let adjustedWidth = rect.width / scale

        // Flip Y coordinate from Vision (bottom-left) to UIKit (top-left)
        let adjustedY = 1.0 - rect.origin.y - rect.height

        return CGRect(
            x: adjustedX * width,
            y: adjustedY * height,
            width: adjustedWidth * width,
            height: rect.height * height
        )
    }
    
    /// Converts a Vision normalised point to UIKit coordinates applying 4:3 aspect fix
    private func convertNormalizedPoint(_ p: CGPoint, to bounds: CGRect) -> CGPoint {
        let width = bounds.width
        let height = bounds.height
        let ratio = (height / width) / (4.0 / 3.0)
        let scale = 1.0 / ratio
        let offsetX = (1.0 - scale) / 2.0
        let adjustedX = (p.x - offsetX) / scale
        let adjustedY = 1.0 - p.y
        return CGPoint(x: adjustedX * width, y: adjustedY * height)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    /// Helper method to find a button with a specific action
    private func findButtonWithAction(_ action: Selector) -> UIButton? {
        return findButtonInView(view, withAction: action)
    }
    
    /// Recursively search for a button with a specific action
    private func findButtonInView(_ view: UIView, withAction action: Selector) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton {
                for target in button.allTargets {
                    let actions = button.actions(forTarget: target, forControlEvent: .touchUpInside) ?? []
                    if actions.contains(action.description) {
                        return button
                    }
                }
            }
            // Recursively search in subviews
            if let foundButton = findButtonInView(subview, withAction: action) {
                return foundButton
            }
        }
        return nil
    }
    
    /// Enhanced text search with validation and error handling
    private func startTextSearchWithValidation(text: String) {
        guard !text.isEmpty else { return }
        
        guard viewModel != nil else { return }
        
        viewModel.startSearchTextWithKeyboard(text: text)
    }
    
    // MARK: - Combine

    /// Bind Combine publishers exposed by the ViewModel.
    private func bindPublishers() {
        viewModel.searchItemNamePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] itemName in
                self?.updateSearchLabel(for: self?.viewModel.currentMode, value: itemName)
            }
            .store(in: &bag)
        
        viewModel.searchTextQueryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] textQuery in
                self?.updateSearchLabel(for: self?.viewModel.currentMode, value: textQuery)
            }
            .store(in: &bag)
        
        viewModel.boundingBoxesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] boxes in
                self?.showBoundingBoxes(boxes)
            }
            .store(in: &bag)

        viewModel.textBoundingBoxPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] box in
                if let box = box {
                    self?.showTextBoundingBox(box)
                } else {
                    for bboxView in self?.boundingBoxViews ?? [] {
                        bboxView.hide()
                    }
                }
            }
            .store(in: &bag)
        
        viewModel.uiClearPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.showBoundingBoxes([])
                for bboxView in self.boundingBoxViews { bboxView.hide() }
            }
            .store(in: &bag)

        bindButtonStates()

        viewModel.readingPausePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.updatePlayPauseButtonTitle(paused: paused)
            }
            .store(in: &bag)

        StopController.shared.didStopAllPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePlayPauseButtonTitle(paused: false)
            }
            .store(in: &bag)

        viewModel.readingClusterQuadPublisher
             .receive(on: DispatchQueue.main)
             .sink { [weak self] quad in
                 if let quad = quad {
                     self?.showCentralClusterQuad(quad)
                 } else {
                     self?.clusterQuadView.hide()
                 }
             }
             .store(in: &bag)
        
        if let sButton = settingsButton {
            sButton.removeTarget(nil, action: nil, for: .touchUpInside)
            sButton.publisher(for: .touchUpInside)
                .sink { [weak self] sender in
                    self?.settingsButtonTap(sender)
                }
                .store(in: &bag)
        }

        if let tButton = tutorialButton {
            tButton.removeTarget(nil, action: nil, for: .touchUpInside)
            tButton.publisher(for: .touchUpInside)
                .sink { [weak self] sender in
                    self?.tutorialButtonTap(sender)
                }
                .store(in: &bag)
        }
        
        SettingsManager.shared.trainingMenuEnabledPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTrainingButtonState()
            }
            .store(in: &bag)
        
        let controlPairs: [(UIButton?, (Any) -> Void)] = [
            (stopButton, { [weak self] sender in self?.stopButtonTap(sender) }),
            (backButton, { [weak self] sender in self?.backButtonTap(sender) }),
            (forwardButton, { [weak self] sender in self?.nextButtonTap(sender) }),
            (zoomMinusButton, { [weak self] sender in self?.zoomMinusButtonTap(sender) }),
            (zoomPlusButton, { [weak self] sender in self?.zoomPlusButtonTap(sender) }),
            (playPauseButton, { [weak self] sender in self?.playPauseButtonTap(sender) }),
            (readTextButton, { [weak self] sender in self?.readTextButtonTap(sender) }),
            (searchItemButton, { [weak self] sender in self?.searchItemButtonTap(sender) }),
            (searchTextButton, { [weak self] sender in self?.searchTextButtonTap(sender) }),
            (toggleReadingSpeedButton, { [weak self] sender in self?.changeReadingSpeedButtonTap(sender) })
        ]

        for (button, action) in controlPairs {
            guard let button = button else { continue }
            button.removeTarget(nil, action: nil, for: .touchUpInside)
            button
                .publisher(for: .touchUpInside)
                .sink(receiveValue: action)
                .store(in: &bag)
        }

        // TODO Pinch-to-zoom gesture recognizer (optional)
        let pinchRecognizer = UIPinchGestureRecognizer()
        view.addGestureRecognizer(pinchRecognizer)
        pinchRecognizer
            .publisher()
            .sink { [weak self] recognizer in
                if let pinch = recognizer as? UIPinchGestureRecognizer {
                    self?.pinch(pinch)
                }
            }
            .store(in: &bag)
        
        viewModel.cameraStablePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.showCameraReadyIndicator()
            }
            .store(in: &bag)

        viewModel.readingPausePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.updatePlayPauseButtonTitle(paused: paused)
            }
            .store(in: &bag)

        viewModel.readingClusterQuadPublisher
             .receive(on: DispatchQueue.main)
             .sink { [weak self] quad in
                 if let quad = quad {
                     self?.showCentralClusterQuad(quad)
                 } else {
                     // Hide when overlay removed
                     self?.clusterQuadView.hide()
                 }
             }
             .store(in: &bag)
        
        // Global stop events – reset Play/Pause label to "Pause" so that stale "Resume" state
        // does not linger after the user presses Stop while paused.
        StopController.shared.didStopAllPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePlayPauseButtonTitle(paused: false)
            }
            .store(in: &bag)
    }
    
    private func bindButtonStates() {
        func wire(_ mode: AppMode, button: UIButton?) {
            guard let button = button else { return }

            viewModel.buttonStatesPublisher
                .map { ($0[mode] ?? .normal) }
                .receive(on: RunLoop.main)
                .sink { [weak button] state in
                    guard let button else { return }
                    // Simple visual states
                    switch state {
                    case .normal:
                        button.alpha = 1.0
                        button.isEnabled = true
                    case .disabled:
                        button.alpha = 0.4
                        button.isEnabled = false
                    case .active:
                        button.alpha = 1.0
                        button.isEnabled = true
                        // Lightweight emphasising animation – keeps behaviour from previous impl
                        UIView.animate(withDuration: 0.15, animations: {
                            button.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                        }, completion: { _ in
                            UIView.animate(withDuration: 0.15) {
                                button.transform = .identity
                            }
                        })
                    }
                }
                .store(in: &bag)
        }

        wire(.searchingItem, button: searchItemButton)
        wire(.searchingText, button: searchTextButton)
        wire(.readingText,  button: readTextButton)

        func wireSecondary(_ sb: SecondaryButton, button: UIButton?) {
            guard let button = button else { return }
            viewModel.secondaryButtonStatesPublisher
                .map { $0[sb] ?? .normal }
                .receive(on: RunLoop.main)
                .sink { [weak button] state in
                    guard let button else { return }
                    switch state {
                    case .normal:
                        button.alpha = 1.0
                        button.isEnabled = true
                    case .disabled:
                        button.alpha = 0.4
                        button.isEnabled = false
                    case .active:
                        button.alpha = 1.0
                        button.isEnabled = true
                        UIView.animate(withDuration: 0.15, animations: {
                            button.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                        }, completion: { _ in
                            UIView.animate(withDuration: 0.15) {
                                button.transform = .identity
                            }
                        })
                    }
                }
                .store(in: &bag)
        }

        wireSecondary(.stop, button: stopButton)
        wireSecondary(.back, button: backButton)
        wireSecondary(.next, button: forwardButton)
        wireSecondary(.zoomOut, button: zoomMinusButton)
        wireSecondary(.zoomIn, button: zoomPlusButton)
        wireSecondary(.toggleSpeed, button: toggleReadingSpeedButton)
    }
}

// MARK: - Delegate Extensions

extension MainViewController: ModalDismissDelegate {
    func modalDidDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.announceMainScreen()
        }
    }
}

extension MainViewController: ItemListViewControllerDelegate {
    func itemListViewController(_ controller: ItemListViewController, didSelectItem item: ItemDisplayInfo) {
        
        // Start search with the selected item using the localized display name
        // This matches voice input behavior where users speak the localized name
        viewModel.startSearchItemFromList(itemName: item.displayName, modelName: item.modelName)
    }
    
    func itemListViewControllerDidCancel(_ controller: ItemListViewController) {
        controller.dismiss(animated: true) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.announceMainScreen()
        }
    }
}

extension MainViewController: TextInputViewControllerDelegate {
    func textInputViewController(_ controller: TextInputViewController, didEnterText text: String) {
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            
            self.startTextSearchWithValidation(text: trimmedText)
        }
    }
    
    func textInputViewControllerDidCancel(_ controller: TextInputViewController) {
        controller.dismiss(animated: true) {}
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.announceMainScreen()
        }
    }
}
