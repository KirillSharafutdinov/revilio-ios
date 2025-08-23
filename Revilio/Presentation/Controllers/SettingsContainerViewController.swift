//
//  SettingsContainerViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

/// Simple container view controller for the Settings modal that handles the close button and title localization
class SettingsContainerViewController: BaseViewController {
    
    // MARK: - IBOutlets
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var closeButton: UIButton!
    
    // MARK: - Properties
    
#if DEBUG
    private var consoleTextView: UITextView!
    private var fpsLabel: UILabel!
    private var sttLabel: UILabel!
#endif
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
#if DEBUG
        setupConsole()
#endif
    }
    
    // MARK: - Actions
    
    @IBAction private func closeButtonTapped(_ sender: Any) {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        dismiss(animated: true) { [weak self] in
            self?.modalDismissDelegate?.modalDidDismiss()
        }
    }
    
    // MARK: - Private Methods
    
    internal override func updateTexts() {
        titleLabel?.accessibilityTraits = .header
        titleLabel?.text = R.string.settings.title()
        titleLabel?.accessibilityHint = R.string.settings.titleHint()
        
        if let button = closeButton {
            setButtonTitle(button, title: R.string.settings.close())
        }
        
        closeButton?.accessibilityHint = R.string.settings.closeHint()
    }
    
    // MARK: - Console setup
#if DEBUG
    private func setupConsole() {
        consoleTextView = UITextView()
        consoleTextView.translatesAutoresizingMaskIntoConstraints = false
        consoleTextView.isEditable = false
        consoleTextView.isSelectable = true
        consoleTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        consoleTextView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        consoleTextView.textColor = .green
        consoleTextView.alpha = 0.0 // Hidden by default; tap title 3 times to toggle
        view.addSubview(consoleTextView)

        NSLayoutConstraint.activate([
            consoleTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            consoleTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            consoleTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            consoleTextView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35)
        ])

        // Toggle gesture – triple-tap on title label shows / hides the console
        let tripleTap = UITapGestureRecognizer()
        tripleTap.numberOfTapsRequired = 3
        titleLabel?.isUserInteractionEnabled = true
        titleLabel?.addGestureRecognizer(tripleTap)
        let toggleCancellable = tripleTap.publisher()
            .sink { [weak self] _ in
                guard let self = self else { return }
                UIView.animate(withDuration: 0.25) { self.consoleTextView.alpha = self.consoleTextView.alpha == 1.0 ? 0.0 : 1.0 }
            }
        bag.add(toggleCancellable)

        // Subscribe to unified log stream via EventBus
        let logCancellable = EventBus.shared.publisher
            .compactMap { event -> String? in
                if case let .log(_, line) = event { return line } else { return nil }
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] line in
                guard let self = self else { return }
                // Append line and keep last ~2000 chars to prevent memory bloat
                let newText = (self.consoleTextView.text + "\n" + line)
                let maxLen = 4000
                if newText.count > maxLen {
                    let suffix = newText.suffix(maxLen)
                    self.consoleTextView.text = String(suffix)
                } else {
                    self.consoleTextView.text = newText
                }
                // Scroll to bottom
                let range = NSMakeRange(self.consoleTextView.text.count - 1, 1)
                self.consoleTextView.scrollRangeToVisible(range)
            }
        bag.add(logCancellable)

        fpsLabel = UILabel()
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        fpsLabel.textColor = .yellow
        view.addSubview(fpsLabel)

        NSLayoutConstraint.activate([
            fpsLabel.trailingAnchor.constraint(equalTo: consoleTextView.trailingAnchor, constant: -4),
            fpsLabel.bottomAnchor.constraint(equalTo: consoleTextView.topAnchor, constant: -4)
        ])

        // Subscribe to FPS lines from EventBus
        let fpsCancellable = EventBus.shared.publisher
            .compactMap { event -> String? in
                if case let .log(_, line) = event { return line } else { return nil }
            }
            .compactMap { line -> String? in
                guard line.contains("FPS:") else { return nil }
                return line.components(separatedBy: "FPS:").last?.trimmingCharacters(in: .whitespaces)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] fps in
                self?.fpsLabel.text = "FPS: \(fps)"
            }
        bag.add(fpsCancellable)

        // ===== Live Speech Transcript label =====
        sttLabel = UILabel()
        sttLabel.translatesAutoresizingMaskIntoConstraints = false
        sttLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        sttLabel.textColor = .cyan
        sttLabel.numberOfLines = 2
        sttLabel.textAlignment = .left
        view.addSubview(sttLabel)

        NSLayoutConstraint.activate([
            sttLabel.leadingAnchor.constraint(equalTo: consoleTextView.leadingAnchor, constant: 4),
            sttLabel.trailingAnchor.constraint(equalTo: fpsLabel.leadingAnchor, constant: -8),
            sttLabel.centerYAnchor.constraint(equalTo: fpsLabel.centerYAnchor)
        ])

        // Subscribe to STT lines via EventBus
        let sttCancellable = EventBus.shared.publisher
            .compactMap { event -> String? in
                if case let .log(_, line) = event { return line } else { return nil }
            }
            .compactMap { line -> String? in
                guard line.contains("STT:") else { return nil }
                return line.components(separatedBy: "STT:").last?.trimmingCharacters(in: .whitespaces)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.sttLabel.text = "STT: " + text
            }
        bag.add(sttCancellable)
    }
#endif
}
