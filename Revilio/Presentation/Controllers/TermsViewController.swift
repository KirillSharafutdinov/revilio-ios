//
//  TermsViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit

class TermsViewController: UIViewController, UIScrollViewDelegate {
    
    private var isAgreed = false {
        didSet {
            continueButton.isEnabled = isAgreed
            continueButton.alpha = isAgreed ? 1.0 : 0.5
            agreementButton.isSelected = isAgreed
        }
    }
    
    private var currentPage: Int = 1
    private var totalPages: Int = 1
    
    // MARK: - UI Components
    
    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(R.string.onboarding.back(), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        btn.tintColor = .white
        btn.layer.cornerRadius = 12
        btn.isEnabled = true
        btn.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = R.string.onboarding.title()
        let fontSize = UIFont.preferredFont(forTextStyle: .title1).pointSize
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        lbl.textAlignment = .center
        return lbl
    }()
    
    private let textView: UITextView = {
        let textView = UITextView()
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.font = UIFont.systemFont(ofSize: 17)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }()
    
    private lazy var agreementButton: UIButton = {
        let btn = UIButton(type: .custom)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        let normalImage = UIImage(systemName: "square", withConfiguration: config)
        let selectedImage = UIImage(systemName: "checkmark.square.fill", withConfiguration: config)
        btn.setImage(normalImage, for: .normal)
        btn.setImage(selectedImage, for: .selected)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 75).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        btn.addTarget(self, action: #selector(toggleAgreement), for: .touchUpInside)
        return btn
    }()
    
    private lazy var agreementLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = R.string.onboarding.agreement()
        lbl.font = .preferredFont(forTextStyle: .body)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isUserInteractionEnabled = true
        lbl.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(toggleAgreement)
        ))
        return lbl
    }()
    
    private lazy var continueButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(R.string.onboarding.continueButton(), for: .normal)
        btn.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.backgroundColor = .systemBlue
        btn.tintColor = .white
        btn.layer.cornerRadius = 12
        btn.isEnabled = false
        btn.alpha = 0.5
        btn.addTarget(self, action: #selector(continueOnboarding), for: .touchUpInside)
        return btn
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        self.usesAdaptiveButtonBackground = true
        
        navigationItem.hidesBackButton = true
        
        setupUI()
        loadTermsText()
        
        scrollView.delegate = self
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(backButton)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        let agreementStack = UIStackView(arrangedSubviews: [agreementButton, agreementLabel])
        agreementStack.spacing = 12
        agreementStack.alignment = .center
        agreementStack.translatesAutoresizingMaskIntoConstraints = false
        
        let mainStack = UIStackView(arrangedSubviews: [titleLabel, textView, agreementStack, continueButton])
        mainStack.axis = .vertical
        mainStack.spacing = 24
        mainStack.setCustomSpacing(40, after: textView)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            backButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            backButton.heightAnchor.constraint(equalToConstant: 50),
            
            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            
            {
                let c = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
                c.priority = .defaultLow // 250
                return c
            }(),
            
            continueButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Helpers
    
    private func loadTermsText() {
        let termsText = R.string.about.termsOfUseContentText()
        let disclaimerText = R.string.about.disclaimerContentText()
        let text = "\(termsText)\n\n\n\(disclaimerText)"
        textView.text = text
        
        textView.sizeToFit()
        textView.layoutIfNeeded()
    }
        
    private func notifyVoiceOverOfScrollPosition() {
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0 else { return }
        
        totalPages = Int(ceil(scrollView.contentSize.height / pageHeight))
        currentPage = Int(ceil(scrollView.contentOffset.y / pageHeight)) + 1
        
        let localizedString = R.string.onboarding.pageIndicator(currentPage, totalPages)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIAccessibility.post(notification: .pageScrolled, argument: localizedString)
        }
    }
    
    // MARK: - UIScrollViewDelegate
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyVoiceOverOfScrollPosition()
    }
        
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            notifyVoiceOverOfScrollPosition()
        }
    }
    
    // MARK: - Actions
    
    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func toggleAgreement() {
        isAgreed.toggle()
        
        UIView.animate(withDuration: 0.2) {
            self.agreementButton.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.agreementButton.transform = .identity
            }
        }
    }
    
    @objc private func continueOnboarding() {
        let batteryWarningVC = BatteryWarningViewController()
        navigationController?.pushViewController(batteryWarningVC, animated: true)
    }
}
