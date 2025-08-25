//
//  AboutContainerViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

/// Simple container view controller for the Settings modal that handles the close button and title localization
class AboutContainerViewController: BaseViewController {
    
    // MARK: - IBOutlets
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var closeButton: UIButton!
    
    // MARK: - Lifecycle
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        announce(text: R.string.about.title())
    }
    
    // MARK: - Private Methods
    
    internal override func updateTexts() {
        titleLabel?.text = R.string.about.title()
        titleLabel?.accessibilityTraits = .header
        
        
        if let button = closeButton {
            setButtonTitle(button, title: R.string.about.close())
        }
        
        closeButton?.accessibilityLabel = R.string.about.close()
        closeButton?.accessibilityHint = R.string.settings.closeHint()
    }
    
    // MARK: - Actions
    
    @IBAction private func closeButtonTapped(_ sender: Any) {
        speechSynthesizer.stopSpeaking()
        
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        
        dismiss(animated: true) { [weak self] in
            self?.modalDismissDelegate?.modalDidDismiss()
        }
    }
} 
