//
//  TrainingViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import CoreHaptics
import AVFoundation
import Combine

/// Describes the logical step currently displayed in the training flow
enum TrainingStep: Int, CaseIterable {
    case forward = 1
    case back
    case pause
    case speed
    case readText
    case findObject
    case findText
    case stop
    case zoomOut
    case zoomIn

    var title: String {
        switch self {
        case .forward:    return R.string.training.forwardTitle()
        case .back:       return R.string.training.backTitle()
        case .pause:      return R.string.training.pauseTitle()
        case .speed:      return R.string.training.speedTitle()
        case .readText:   return R.string.training.readTextTitle()
        case .findObject: return R.string.training.findObjectTitle()
        case .findText:   return R.string.training.findTextTitle()
        case .stop:       return R.string.training.stopTitle()
        case .zoomOut:    return R.string.training.zoomOutTitle()
        case .zoomIn:     return R.string.training.zoomInTitle()
        }
    }
}

/// Controller that helps blind / low-vision users learn the spatial placement and functionality
/// of the main-screen controls.  While the user drags their finger across the
/// screen, the app provides continuous haptic feedback **only** while the touch
/// is inside the button being taught in the current step.  Releasing the finger
/// (or leaving the buttonʼs frame) immediately stops feedback.
final class TrainingViewController: BaseViewController {

    // MARK: - UI Elements
    private let instructionLabel = UILabel()
    private let closeTutorialButton    = UIButton(type: .system)
    private let detailsButton   = UIButton(type: .system)

    private let forwardButton    = UIButton(type: .system)
    private let backButton       = UIButton(type: .system)
    private let pauseButton      = UIButton(type: .system)
    private let speedButton      = UIButton(type: .system)
    private let readTextButton   = UIButton(type: .system)
    private let findObjectButton = UIButton(type: .system)
    private let findTextButton   = UIButton(type: .system)
    private let stopButton       = UIButton(type: .system)
    private let zoomOutButton    = UIButton(type: .system)
    private let zoomInButton     = UIButton(type: .system)
    
    // MARK: - Private State
    
    private let step: TrainingStep
    private var explorationController: ButtonExplorationHapticController?
    /// Remaining text when user pauses on the «Pause» step (to allow resume)
    private var pausedRemainingText: String?
        
    // MARK: - Lifecycle
    required init?(coder: NSCoder) {
        // Fallback to first step when instantiated from storyboard
        self.step = .forward
        super.init(coder: coder)
    }
    
    init(step: TrainingStep = .forward) {
        self.step = step
        super.init(nibName: nil, bundle: nil)
    }

    convenience init() {
        self.init(step: .forward)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        configureExplorationHaptics()
        
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        explorationController?.endExploration()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        speakCurrentExplanation()
    }

    // MARK: - UI Configuration

    private func setupUI() {
        let makeHorizontalStack: () -> UIStackView = {
            let s = UIStackView()
            s.axis = .horizontal
            s.distribution = .fillEqually
            s.spacing = 6
            return s
        }

        // ===== 1. Top row – details + dismiss (swapped positions)
        let stack1 = makeHorizontalStack()
        configureDetailsButton()
        stack1.addArrangedSubview(detailsButton)
        
        configureDismissButton()
        stack1.addArrangedSubview(closeTutorialButton)

        // ===== 2. Instruction text describing the controlʼs location
        let stack2 = makeHorizontalStack()
        configureInstruction()
        // stack2.addArrangedSubview(instructionLabel)

        // ===== 3. Additional description (what happens on tap)
        let stack3 = makeHorizontalStack()
        let detailLabel = UILabel()
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        detailLabel.text = shortDescription(for: step)
        detailLabel.font = UIFont.preferredFont(forTextStyle: .body)
        // stack3.addArrangedSubview(detailLabel)

        // ===== 4-8. Replica of main-screen button grid
        let stack4 = makeHorizontalStack()
        if step.rawValue >= TrainingStep.pause.rawValue {
            configurePauseButton()
            stack4.addArrangedSubview(pauseButton)
        } else {
            stack4.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .pause)))
        }

        let stack5 = makeHorizontalStack()
        if step.rawValue >= TrainingStep.findObject.rawValue {
            configureFindObjectButton()
            stack5.addArrangedSubview(findObjectButton)
        } else {
            stack5.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .findObject)))
        }
        if step.rawValue >= TrainingStep.speed.rawValue {
            configureSpeedButton()
            stack5.addArrangedSubview(speedButton)
        } else {
            stack5.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .speed)))
        }
        // Back button active on steps starting from .back
        if step.rawValue >= TrainingStep.back.rawValue {
            configureBackButton()
            stack5.addArrangedSubview(backButton)
        } else {
            stack5.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .back)))
        }

        let stack6 = makeHorizontalStack() // «НАЙТИ ТЕКСТ», «ЧИТАТЬ ТЕКСТ», «ВПЕРЁД»
        if step.rawValue >= TrainingStep.findText.rawValue {
            configureFindTextButton()
            stack6.addArrangedSubview(findTextButton)
        } else {
            stack6.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .findText)))
        }
        if step.rawValue >= TrainingStep.readText.rawValue {
            configureReadTextButton()
            stack6.addArrangedSubview(readTextButton)
        } else {
            stack6.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .readText)))
        }
        configureForwardButton()
        stack6.addArrangedSubview(forwardButton)

        let stack7 = makeHorizontalStack()
        if step.rawValue >= TrainingStep.stop.rawValue {
            configureStopButton()
            stack7.addArrangedSubview(stopButton)
        } else {
            stack7.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .stop)))
        }

        let stack8 = makeHorizontalStack()
        if step.rawValue >= TrainingStep.zoomOut.rawValue {
            configureZoomOutButton()
            stack8.addArrangedSubview(zoomOutButton)
        } else {
            stack8.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .zoomOut)))
        }
        if step.rawValue >= TrainingStep.zoomIn.rawValue {
            configureZoomInButton()
            stack8.addArrangedSubview(zoomInButton)
        } else {
            stack8.addArrangedSubview(makePlaceholderButton(title: buttonLabel(for: .zoomIn)))
        }

        // ===== Composite vertical stack
        let mainStack = UIStackView(arrangedSubviews: [stack1, stack2, stack3, stack4, stack5, stack6, stack7, stack8])
        mainStack.axis = .vertical
        mainStack.spacing = 6
        mainStack.distribution = .fillEqually
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 5),
            mainStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -5),
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Button Configuration
    private func makePlaceholderButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 22)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.isEnabled = false
        return button
    }

    private func configureDismissButton() {
        closeTutorialButton.setTitle(R.string.main.close(), for: .normal)
        closeTutorialButton.setTitleColor(.label, for: .normal)
        closeTutorialButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        closeTutorialButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
                self.dismissTraining()
            }
            .store(in: &bag)
    }

    private func configureDetailsButton() {
        detailsButton.setTitle(R.string.training.details(), for: .normal)
        detailsButton.setTitleColor(.label, for: .normal)
        detailsButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        detailsButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
                self.detailsPressed()
            }
            .store(in: &bag)
    }

    private func configureForwardButton() {
        forwardButton.setTitle(buttonLabel(for: .forward), for: .normal)
        forwardButton.setTitleColor(.label, for: .normal)
        forwardButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        forwardButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.nextPressed() }
            .store(in: &bag)
        forwardButton.isEnabled = true // Allow progressing from the very first step
    }

    private func configureBackButton() {
        backButton.setTitle(buttonLabel(for: .back), for: .normal)
        backButton.setTitleColor(.label, for: .normal)
        backButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        backButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.previousPressed() }
            .store(in: &bag)
        backButton.isAccessibilityElement = false
        backButton.accessibilityElementsHidden = true
    }

    private func configurePauseButton() {
        pauseButton.setTitle(buttonLabel(for: .pause), for: .normal)
        pauseButton.setTitleColor(.label, for: .normal)
        pauseButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        pauseButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.pausePressed() }
            .store(in: &bag)
    }

    private func configureSpeedButton() {
        speedButton.setTitle(buttonLabel(for: .speed), for: .normal)
        speedButton.setTitleColor(.label, for: .normal)
        speedButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        speedButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.speedPressed() }
            .store(in: &bag)
    }

    private func configureFindObjectButton() {
        findObjectButton.setTitle(buttonLabel(for: .findObject), for: .normal)
        findObjectButton.setTitleColor(.label, for: .normal)
        findObjectButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        findObjectButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.findObjectPressed() }
            .store(in: &bag)
    }

    private func configureReadTextButton() {
        readTextButton.setTitle(buttonLabel(for: .readText), for: .normal)
        readTextButton.setTitleColor(.label, for: .normal)
        readTextButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        readTextButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.readTextPressed() }
            .store(in: &bag)
    }

    private func configureFindTextButton() {
        findTextButton.setTitle(buttonLabel(for: .findText), for: .normal)
        findTextButton.setTitleColor(.label, for: .normal)
        findTextButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        findTextButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.findTextPressed() }
            .store(in: &bag)
    }

    private func configureStopButton() {
        stopButton.setTitle(buttonLabel(for: .stop), for: .normal)
        stopButton.setTitleColor(.label, for: .normal)
        stopButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        stopButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.stopPressed() }
            .store(in: &bag)
    }

    private func configureZoomOutButton() {
        zoomOutButton.setTitle(buttonLabel(for: .zoomOut), for: .normal)
        zoomOutButton.setTitleColor(.label, for: .normal)
        zoomOutButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        zoomOutButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.zoomOutPressed() }
            .store(in: &bag)
    }

    private func configureZoomInButton() {
        zoomInButton.setTitle(buttonLabel(for: .zoomIn), for: .normal)
        zoomInButton.setTitleColor(.label, for: .normal)
        zoomInButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        zoomInButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.zoomInPressed() }
            .store(in: &bag)
    }
    
    private func configureInstruction() {
        instructionLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        instructionLabel.numberOfLines = 0
        instructionLabel.textAlignment = .center
        instructionLabel.text = navigation(for: step)
        instructionLabel.accessibilityLabel = instructionLabel.text
    }

    // MARK: - User Actions
    
    @objc private func dismissTraining() {
        speechSynthesizer.stopSpeaking()

        if let windowRoot = view.window?.rootViewController {
            windowRoot.dismiss(animated: true) { [weak self] in
                self?.modalDismissDelegate?.modalDidDismiss()
            }
        } else {
            var presenter = presentingViewController
            while let next = presenter?.presentingViewController { presenter = next }
            presenter?.dismiss(animated: true) { [weak self] in
                self?.modalDismissDelegate?.modalDidDismiss()
            }
        }
    }
    
    @objc private func detailsPressed() {
        speechSynthesizer.stopSpeaking()
        speechSynthesizer.speak(text: longDescription(for: step))
    }
    
    @objc private func nextPressed() {
        speechSynthesizer.stopSpeaking()

        // Move to next training step if available. If we are already on the
        // last step, simply inform the user that the training has finished
        // using both speech and a continuous haptic signal.
        if let next = TrainingStep(rawValue: step.rawValue + 1) {
            hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
            
            let vc = TrainingViewController(step: next)
            vc.modalPresentationStyle = .fullScreen
            present(vc, animated: true)
        } else {
            hapticFeedbackManager.playPattern(.continuous, intensity: 1.0)
            speechSynthesizer.speak(text: R.string.training.completed())
        }
    }

    @objc private func previousPressed() {
        speechSynthesizer.stopSpeaking()
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        
        if let prev = TrainingStep(rawValue: step.rawValue - 1) {
            
            let vc = TrainingViewController(step: prev)
            vc.modalPresentationStyle = .fullScreen
            present(vc, animated: true)
        }
    }
    
    @objc private func pausePressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)

        if speechSynthesizer.isSpeaking {
            // Pause and remember the remaining text
            pausedRemainingText = speechSynthesizer.pauseSpeaking()
        } else if let remaining = pausedRemainingText {
            // Resume from the precise point
            speechSynthesizer.speak(text: remaining)
            pausedRemainingText = nil
        }
    }

    @objc private func speedPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.toggleReadingSpeed()
    }
    
    @objc private func readTextPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.speak(text: buttonLabel(for: .readText))
    }
    
    @objc private func findObjectPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.speak(text: buttonLabel(for: .findObject))
    }

    @objc private func findTextPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.speak(text: buttonLabel(for: .findText))
    }

    @objc private func stopPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.speak(text: buttonLabel(for: .stop))
    }

    @objc private func zoomOutPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.speak(text: buttonLabel(for: .zoomOut))
    }

    @objc private func zoomInPressed() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        speechSynthesizer.speak(text: buttonLabel(for: .zoomIn))
    }
    
    // MARK: - Speech & Feedback

    private func speakCurrentExplanation() {
        speechSynthesizer.stopSpeaking()
        
        let phrase = shortDescription(for: step) + " " + navigation(for: step)
        speechSynthesizer.speak(text: phrase)
    }
    
    // MARK: - Haptic Feedback
    private func configureExplorationHaptics() {
        // Weʼll provide exploration **only** for the button of the current step
        let targetButton: UIButton
        switch step {
        case .forward:    targetButton = forwardButton
        case .back:       targetButton = backButton
        case .pause:      targetButton = pauseButton
        case .speed:      targetButton = speedButton
        case .readText:   targetButton = readTextButton
        case .findObject: targetButton = findObjectButton
        case .findText:   targetButton = findTextButton
        case .stop:       targetButton = stopButton
        case .zoomOut:    targetButton = zoomOutButton
        case .zoomIn:     targetButton = zoomInButton
        }
        explorationController = ButtonExplorationHapticController(buttons: [targetButton],
                                                                  hapticManager: hapticFeedbackManager)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleExploreGesture(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false // Allow normal button taps
        view.addGestureRecognizer(pan)
    }

    @objc private func handleExploreGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began, .changed:
            explorationController?.updateTouchLocation(location, in: view)
        case .ended, .cancelled, .failed:
            explorationController?.endExploration()
        default:
            break
        }
    }
    // MARK: - Localization

    private func buttonLabel(for step: TrainingStep) -> String {
        switch step {
        case .forward:    return R.string.main.forward()
        case .back:       return R.string.main.back()
        case .pause:      return R.string.main.pause()
        case .speed:      return R.string.main.toggleReadingSpeed()
        case .readText:   return R.string.main.readText()
        case .findObject: return R.string.main.searchItem()
        case .findText:   return R.string.main.searchText()
        case .stop:       return R.string.main.stop()
        case .zoomOut:    return R.string.main.zoomOut()
        case .zoomIn:     return R.string.main.zoomIn()
        }
    }
    
    /// Short description spoken automatically when a step is shown.
    private func shortDescription(for step: TrainingStep) -> String {
        switch step {
        case .forward:    return R.string.training.forwardShortDescription()
        case .back:       return R.string.training.backShortDescription()
        case .pause:      return R.string.training.pauseShortDescription()
        case .speed:      return R.string.training.speedShortDescription()
        case .readText:   return R.string.training.readTextShortDescription()
        case .findObject: return R.string.training.findObjectShortDescription()
        case .findText:   return R.string.training.findTextShortDescription()
        case .stop:       return R.string.training.stopShortDescription()
        case .zoomOut:    return R.string.training.zoomOutShortDescription()
        case .zoomIn:     return R.string.training.zoomInShortDescription()
        }
    }

    /// Detailed description spoken when the user presses the "Details" button.
    private func longDescription(for step: TrainingStep) -> String {
        switch step {
        case .forward:    return R.string.training.forwardDetailDescription()
        case .back:       return R.string.training.backDetailDescription()
        case .pause:      return R.string.training.pauseDetailDescription()
        case .speed:      return R.string.training.speedDetailDescription()
        case .readText:   return R.string.training.readTextDetailDescription()
        case .findObject: return R.string.training.findObjectDetailDescription()
        case .findText:   return R.string.training.findTextDetailDescription()
        case .stop:       return R.string.training.stopDetailDescription()
        case .zoomOut:    return R.string.training.zoomOutDetailDescription()
        case .zoomIn:     return R.string.training.zoomInDetailDescription()
        }
    }

    private func navigation(for step: TrainingStep) -> String {
        switch step {
        case .forward:    return R.string.training.firstLocation()
        case .back:       return R.string.training.midLocation()
        case .pause:      return R.string.training.midLocation()
        case .speed:      return R.string.training.midLocation()
        case .readText:   return R.string.training.midLocation()
        case .findObject: return R.string.training.midLocation()
        case .findText:   return R.string.training.midLocation()
        case .stop:       return R.string.training.midLocation()
        case .zoomOut:    return R.string.training.midLocation()
        case .zoomIn:     return R.string.training.lastLocation()
        }
    }

    // MARK: - Localization Handling
    
    /// Updates all text elements in the training view
    internal override func updateTexts() {
        // Update instruction label
        instructionLabel.text = navigation(for: step)
                
        closeTutorialButton.setTitle(R.string.main.close(), for: .normal)
        detailsButton.setTitle(R.string.training.details(), for: .normal)
        
        forwardButton.setTitle(R.string.main.forward(), for: .normal)
        backButton.setTitle(R.string.main.back(), for: .normal)
        pauseButton.setTitle(R.string.main.pause(), for: .normal)
        speedButton.setTitle(R.string.main.toggleReadingSpeed(), for: .normal)
        readTextButton.setTitle(R.string.main.readText(), for: .normal)
        findObjectButton.setTitle(R.string.main.searchItem(), for: .normal)
        findTextButton.setTitle(R.string.main.searchText(), for: .normal)
        stopButton.setTitle(R.string.main.stop(), for: .normal)
        zoomOutButton.setTitle(R.string.main.zoomOut(), for: .normal)
        zoomInButton.setTitle(R.string.main.zoomIn(), for: .normal)
    }
    
    /// Updates accessibility labels for all UI elements
    internal override func setupAccessibility() {
        // Update main instruction accessibility
        instructionLabel.accessibilityLabel = navigation(for: step)
        
        // Update view accessibility
        view.accessibilityLabel = R.string.training.title()
    }
}

// MARK: - Haptic Controller

/// Drives continuous haptic feedback while the userʼs touch is inside any of
/// the **registered** buttons.  Meant to be reused across multiple tutorial
/// steps as the buttons change.
fileprivate final class ButtonExplorationHapticController {
    private let buttons: [UIButton]
    private let hapticManager: HapticFeedbackRepository
    private weak var currentButton: UIButton?
    private var repeatTimer: Timer?
    
    init(buttons: [UIButton], hapticManager: HapticFeedbackRepository) {
        self.buttons = buttons
        self.hapticManager = hapticManager
    }
    
    func updateTouchLocation(_ location: CGPoint, in container: UIView) {
        let hitButton = buttons.first { btn in
            let frameInContainer = btn.convert(btn.bounds, to: container)
            return frameInContainer.contains(location)
        }
        
        // Handle state transitions: outside → inside OR inside → different / none
        if hitButton != currentButton {
            if currentButton != nil {
                hapticManager.stop()
                repeatTimer?.invalidate()
                repeatTimer = nil
            }
            
            if hitButton != nil {
                self.startRepeatingHaptics()
            }
            currentButton = hitButton
        }
    }
    
    func endExploration() {
        currentButton = nil
        hapticManager.stop()
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
    
    private func startRepeatingHaptics() {
        hapticManager.playPattern(.continuous, intensity: 1.0)

        repeatTimer?.invalidate()

        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.hapticManager.playPattern(.continuous, intensity: 1.0)
        }
    }
}
