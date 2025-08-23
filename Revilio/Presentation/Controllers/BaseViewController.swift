//
//  BaseViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine
import AVFoundation

/// Provides foundational infrastructure for view controllers, managing common dependencies,
/// accessibility settings, and language localization. Handles VoiceOver status changes,
/// speech synthesis, and modal dismissal coordination. Serves as base class for specialized
/// view controllers with shared functionality and consistent behavior across the application.
class BaseViewController: UIViewController {
    
    // MARK: - Common Dependencies
    @Inject var speechSynthesizer: SpeechSynthesizerRepository
    @Inject var hapticFeedbackManager: HapticFeedbackRepository
    
    // MARK: - Common Properties
    var bag = OperationBag()
    var isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    weak var modalDismissDelegate: ModalDismissDelegate?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.backgroundColor = .systemBackground
        self.usesAdaptiveButtonBackground = true
        
        setupAccessibility()
        updateTexts()
        subscribeToLanguageChanges()
        subscribeToVoiceOverChanges()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        speechSynthesizer.stopSpeaking()
    }
    
    // MARK: - Common Setup
    private func subscribeToLanguageChanges() {
        LocalizationManager.shared.languagePublisher
            .sink { [weak self] _ in
                self?.languageChanged()
            }
            .store(in: &bag)
    }
    
    private func subscribeToVoiceOverChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Overridable Methods
    func updateTexts() {
        // To be overridden
    }
    
    func setupAccessibility() {
        // To be overridden
    }
    
    func announceScreenIfNeeded() {
        // To be overridden
    }
    
    // MARK: - Common Handlers
    @objc func languageChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTexts()
            self?.setupAccessibility()
            self?.view.layoutIfNeeded()
        }
    }
    
    @objc func voiceOverStatusChanged() {
        isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    }
    
    func announce(text: String) {
        guard !isVoiceOverRunning else { return }

        speechSynthesizer.resumeOutput()
        speechSynthesizer.stopSpeaking()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.speechSynthesizer.speak(text: text)
        }
    }
    
    func setButtonTitle(_ button: UIButton, title: String) {
        if var configuration = button.configuration {
            configuration.attributedTitle = nil
            configuration.title = title
            button.configuration = configuration
        } else {
            button.setTitle(title, for: .normal)
        }
    }
    
    func performDismiss(completion: (() -> Void)? = nil) {
        dismiss(animated: true) { [weak self] in
            self?.modalDismissDelegate?.modalDidDismiss()
            completion?()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
