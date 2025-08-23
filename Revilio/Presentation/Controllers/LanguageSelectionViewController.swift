//
//  LanguageSelectionViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit

enum AppStorageKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
}

class LanguageSelectionViewController: UIViewController {
    
    private let languages: [AppLanguage] = [.ru, .en, .zhHans]
    private var buttons: [UIButton] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.usesAdaptiveButtonBackground = true
        
        setupUI()
        
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        let languageLabel = UILabel()
        languageLabel.text = R.string.onboarding.languagePrompt()
        languageLabel.font = .preferredFont(forTextStyle: .title2)
        languageLabel.textAlignment = .center
        languageLabel.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        stackView.addArrangedSubview(languageLabel)
        stackView.setCustomSpacing(32, after: languageLabel)
        
        for (index, language) in languages.enumerated() {
            let button = createLanguageButton(for: language, tag: index)
            stackView.addArrangedSubview(button)
            buttons.append(button)
        }
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func createLanguageButton(for language: AppLanguage, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        
        let title: String
        switch language {
        case .ru: title = R.string.onboarding.languageRussian()
        case .en: title = R.string.onboarding.languageEnglish()
        case .zhHans: title = R.string.onboarding.languageChinese()
        }
        
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(self, action: #selector(languageSelected(_:)), for: .touchUpInside)
        return button
    }
    
    @objc private func languageSelected(_ sender: UIButton) {
        let selectedLanguage = languages[sender.tag]
        LocalizationManager.shared.set(language: selectedLanguage)
        
        navigationItem.backBarButtonItem = UIBarButtonItem(
            title: R.string.onboarding.back(),
            style: .plain,
            target: nil,
            action: nil
        )
        
        let termsVC = TermsViewController()
        navigationController?.pushViewController(termsVC, animated: true)
    }
}
