//
//  AboutViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import SafariServices
import MessageUI
import Combine

class AboutViewController: BaseTableViewController, MFMailComposeViewControllerDelegate, ModalDismissDelegate {
    
    // MARK: - Outlets
    
    @IBOutlet weak var logoImageView: UIImageView!
    @IBOutlet weak var appNameVersionLabel: UILabel!
    @IBOutlet weak var copyrightLabel: UILabel!
    @IBOutlet weak var appDescriptionLabel: UILabel!
    
    @IBOutlet weak var termsOfUseLabel: UILabel!
    @IBOutlet weak var privacyLabel: UILabel!
    @IBOutlet weak var disclaimerLabel: UILabel!
    
    @IBOutlet weak var emailDeveloperLabel: UILabel!
    
    @IBOutlet weak var agplLabel: UILabel!
    @IBOutlet weak var linkGithubLabel: UILabel!
    @IBOutlet weak var openSourceLicensesLabel: UILabel!
    
    // MARK: - Constants for table structure
    
    private enum Section: Int {
        case appInfo = 0
        case legal = 1
        case support = 2
        case licenses = 3
    }
    
    // MARK: - Links
    private let privacyLink: String = "https://kirillsharafutdinov.github.io/revilio/privacy-policy.html"
    private let disclaimerLink: String = "https://yourdomain.example/disclaimer"
    private let gitHubLink: String = "https://github.com/KirillSharafutdinov/revilio-ios"
    private let agplLink: String = "https://www.gnu.org/licenses/agpl-3.0.html"

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateIcon()
        tableView.rowHeight = 60
    }
    
    // MARK: - Helpers
    
    private func updateIcon() {
        logoImageView.image = UIImage(named: "r11-3-1024")
        logoImageView.layer.cornerRadius = 12
        logoImageView.clipsToBounds = true
    }
    
    internal override func updateTexts() {
        appDescriptionLabel?.text = R.string.about.appDestriptionCellTitle()
        termsOfUseLabel?.text = R.string.about.termsOfUseCellTitle()
        privacyLabel?.text = R.string.about.privacyPolicyCellTitle()
        disclaimerLabel?.text = R.string.about.disclaimerCellTitle()
        agplLabel?.text = R.string.about.agplCellTitle()
        linkGithubLabel?.text = R.string.about.githubCellTitle()
        openSourceLicensesLabel?.text = R.string.about.thirdPartyComponentsCellTitle()
        
        let feedbackLabel = R.string.about.feedbackCellTitle()
        let email = R.string.about.feedbackEmail()
        emailDeveloperLabel?.text = "\(feedbackLabel): \(email)"
        
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        appNameVersionLabel.text = "Revilio. \(R.string.about.version()): \(version) (\(R.string.about.build()): \(build))"
        
        let currentYear = Calendar.current.component(.year, from: .now)
        copyrightLabel.text = currentYear != 2025 ?
        "© (2025-\(currentYear)) Kirill Sharafutdinov" :
        "© (\(currentYear)) Kirill Sharafutdinov"
    }

    private func fillDynamicData() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        appNameVersionLabel.text = "Revilio. \(R.string.about.version()):  \(version) (\(R.string.about.build()): \(build))"
        
        let currentYear = Calendar.current.component(.year, from: .now)
        if currentYear != 2025 {
            copyrightLabel.text = "© (2025-\(currentYear)) Kirill Sharafutdinov"
        } else {
            copyrightLabel.text = "© (\(currentYear)) Kirill Sharafutdinov"
        }
    }

    // MARK: - TableView selection
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .appInfo:
            if indexPath.row == 2 { showDescription() }
        case .legal:
            handleLegalLinks(row: indexPath.row)
        case .support:
            if indexPath.row == 0 { composeMail() }
        case .licenses:
            handleLicense(row: indexPath.row)
        default:
            break
        }
    }
    
    private func handleLegalLinks(row: Int) {
        if row == 0 {
            showTermsOfUse()
        } else if row == 1 {
            openPrivacyPolicy()
        } else if row == 2 {
            showDisclaimer()
        }
    }

    private func handleLicense(row: Int) {
        if row == 0 {
            openAGPL()
        } else if row == 1 {
            openGitHub()
        } else if row == 2 {
            showLicenses()
        }
    }

    // MARK: - Actions
    private func showDescription() {
        presentContentViewController(
            titleProvider: { R.string.about.appDestriptionCellTitle() },
            contentTextProvider: { R.string.about.appDescriptionContentText() }
        )
    }
    
    private func showTermsOfUse() {
        let linksProvider: () -> [String: String] = {
            return [
                R.string.about.showTermsOfUsePrivacyPolicyLinkText(): self.privacyLink,
                R.string.about.showTermsOfUseDisclaimerLinkText(): self.disclaimerLink,
                "AGPL-3.0": self.agplLink
            ]
        }
        
        presentContentViewController(
            titleProvider: { R.string.about.termsOfUseCellTitle() },
            contentTextProvider: { R.string.about.termsOfUseContentText() },
            linksProvider: linksProvider
        )
    }
    
    private func openPrivacyPolicy() {
        guard let url = URL(string: privacyLink) else { return }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }
    
    private func showDisclaimer() {
        let linksProvider: () -> [String: String] = {
            return [
                R.string.about.disclaimerPrivacyPolicyLinkText(): self.privacyLink
            ]
        }
        
        presentContentViewController(
            titleProvider: { R.string.about.disclaimerShortTitle() },
            contentTextProvider: { R.string.about.disclaimerContentText() },
            linksProvider: linksProvider
        )
    }
    
    private func openAGPL() {
        guard let url = URL(string: agplLink) else { return }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    private func composeMail() {
        guard MFMailComposeViewController.canSendMail() else { return }
        let mail = MFMailComposeViewController()
        mail.setToRecipients([R.string.about.feedbackEmail()])
        mail.setSubject(R.string.about.emailSubject())
        mail.mailComposeDelegate = self
        present(mail, animated: true)
    }
    
    private func openGitHub() {
        guard let url = URL(string: gitHubLink) else { return }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    private func showLicenses() {
        let linksProvider: () -> [String: String] = {
            return [
                R.string.about.thirdPartyComponentsGithubLinkText(): self.gitHubLink,
                "https://github.com/mac-cain13/R.swift": "https://github.com/mac-cain13/R.swift",
                "https://github.com/mac-cain13/R.swift/blob/main/License": "https://github.com/mac-cain13/R.swift/blob/main/License",
                "https://github.com/ultralytics": "https://github.com/ultralytics",
                "https://github.com/ultralytics/ultralytics/blob/main/LICENSE": "https://github.com/ultralytics/ultralytics/blob/main/LICENSE"
            ]
        }
        
        presentContentViewController(
            titleProvider: { R.string.about.thirdPartyComponentsCellTitle() },
            contentTextProvider: { R.string.about.thirdPartyComponentsContentText() },
            linksProvider: linksProvider
        )
    }
    
    private func presentContentViewController(titleProvider: @escaping () -> String,
                                              contentTextProvider: @escaping () -> String,
                                              linksProvider: (() -> [String: String])? = nil
    ){
        if presentedViewController != nil {
            dismiss(animated: false) { [weak self] in
                self?.presentContentViewController(titleProvider: titleProvider,
                                                   contentTextProvider: contentTextProvider,
                                                   linksProvider: linksProvider
                )
            }
            return
        }
        
        let vc = ContentViewController(
            titleProvider: titleProvider,
            contentTextProvider: contentTextProvider,
            linksProvider: linksProvider
        )
        vc.modalDismissDelegate = self

        vc.modalPresentationStyle = .fullScreen
        
        present(vc, animated: true) {}
    }

    // MARK: - MFMailComposeViewControllerDelegate
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
    
    func modalDidDismiss() {
        announce(text: R.string.about.title())
    }
}

    // MARK: - Content VC

/// Simple content Text VC to show some app info if needed.
class ContentViewController: BaseViewController, UITextViewDelegate {
    // MARK: - UI Elements
    
    /// Header
    private let topContainer: UIView = {
        let view = UIView()
        view.backgroundColor =  .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "title"
        label.font = UIFont.boldSystemFont(ofSize: 28)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(R.string.textInput.close(), for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 10
        button.accessibilityHint = R.string.itemList.accessibilityCloseHint()
        button.accessibilityTraits = [.button]
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private let textView: UITextView = {
        let textView = UITextView()
        textView.text = "placeHolderText"
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    // MARK: - Properties
    private let titleProvider: () -> String
    private let contentTextProvider: () -> String
    private let linksProvider: (() -> [String: String])?

    init(titleProvider: @escaping () -> String,
         contentTextProvider: @escaping () -> String,
         linksProvider: (() -> [String: String])? = nil
    ){
        self.titleProvider = titleProvider
        self.contentTextProvider = contentTextProvider
        self.linksProvider = linksProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
                
        setupUI()
        setupConstraints()
        
        textView.delegate = self
        textView.setContentOffset(.zero, animated: false)
        
        view.layoutIfNeeded()
        
        let closeC = closeButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in
                self?.dismissContent()
                self?.dismiss(animated: true)
            }
        bag.add(closeC)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let text = "\(titleProvider()). \(contentTextProvider())"
        announce(text: text)
    }
    
    // MARK: - Helpers
    
    private func setupUI() {
        view.addSubview(topContainer)
        topContainer.addSubview(titleLabel)
        topContainer.addSubview(closeButton)
        view.addSubview(scrollView)
        scrollView.addSubview(textView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            topContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            topContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            {
                let c = topContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
                c.priority = .defaultHigh // 750
                return c
            }()
        ])
        
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: topContainer.centerXAnchor, constant: 3),
            closeButton.trailingAnchor.constraint(equalTo: topContainer.trailingAnchor, constant: -6),
            {
                let c = closeButton.topAnchor.constraint(equalTo: topContainer.topAnchor, constant: 6)
                c.priority = .defaultHigh
                return c
            }(),
            {
                let c = closeButton.bottomAnchor.constraint(equalTo: topContainer.bottomAnchor, constant: -6)
                c.priority = .defaultHigh
                return c
            }(),
            {
                let c = closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 84)
                c.priority = .defaultHigh
                return c
            }()
        ])
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: topContainer.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: topContainer.centerXAnchor, constant: -3),
            titleLabel.centerYAnchor.constraint(equalTo: topContainer.centerYAnchor)
        ])
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topContainer.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            textView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }
    
    // MARK: - Content Update
    internal override func updateTexts() {
        titleLabel.text = titleProvider()
        closeButton.setTitle(R.string.textInput.close(), for: .normal)
        closeButton.accessibilityHint = R.string.itemList.accessibilityCloseHint()
        setupTextView()
    }
    
    private func setupTextView() {
        let contentText = contentTextProvider()
        let links = linksProvider?() ?? [:]
        
        let attributedString = NSMutableAttributedString(string: contentText)
        let entireRange = NSRange(location: 0, length: attributedString.length)
        
        attributedString.addAttributes([
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ], range: entireRange)
        
        if !links.isEmpty {
            for (linkText, urlString) in links {
                if let range = contentText.range(of: linkText) {
                    let nsRange = NSRange(range, in: contentText)
                    if let url = URL(string: urlString) {
                        attributedString.addAttribute(.link, value: url, range: nsRange)
                    }
                }
            }
        }
        
        textView.attributedText = attributedString
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
    }
    
    @objc private func dismissContent() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        dismiss(animated: true) { [weak self] in
            self?.modalDismissDelegate?.modalDidDismiss()
        }
    }
}
