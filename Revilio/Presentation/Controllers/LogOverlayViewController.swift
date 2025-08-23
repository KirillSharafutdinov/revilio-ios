//
//  LogOverlayViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

#if DEBUG
/// Floating overlay that shows the latest log lines in real-time. Installed once from
/// `DependencyContainer` in DEBUG builds. Non-intrusive and can be dismissed with a two-finger tap.
final class LogOverlayViewController: UIViewController {
    private let textView = UITextView()
    private let clearButton = UIButton(type: .custom)
    private let searchBar = UISearchBar()
    private let hideButton = UIButton(type: .custom)
    private let collapseButton = UIButton(type: .custom)
    private var bag = OperationBag()
    private var maxLines: Int = 200
    private var allLines: [NSAttributedString] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        textView.backgroundColor = .clear
        textView.textColor = .green
        textView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        // Configure clear button appearance
        clearButton.setTitle("⌫", for: .normal)
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        clearButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        clearButton.layer.cornerRadius = 10
        clearButton.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)

        // Configure hide button appearance (👁 icon)
        hideButton.setTitle("👁", for: .normal)
        hideButton.setTitleColor(.white, for: .normal)
        hideButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        hideButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        hideButton.layer.cornerRadius = 10
        hideButton.addTarget(self, action: #selector(dismissOverlay), for: .touchUpInside)

        // Configure collapse button appearance (▼ / ▲)
        collapseButton.setTitle("▼", for: .normal)
        collapseButton.setTitleColor(.white, for: .normal)
        collapseButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        collapseButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        collapseButton.layer.cornerRadius = 10
        collapseButton.addTarget(self, action: #selector(toggleCollapse), for: .touchUpInside)

        view.addSubview(searchBar)
        view.addSubview(textView)
        view.addSubview(clearButton)
        view.addSubview(hideButton)
        view.addSubview(collapseButton)
        textView.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Search bar constraints (top, full width)
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: view.topAnchor),
            // TextView below search bar
            textView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            // Clear button constraints (size 20×20 below search bar right corner)
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20),
            clearButton.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            // Hide button constraints (same size next to clear button)
            hideButton.widthAnchor.constraint(equalToConstant: 20),
            hideButton.heightAnchor.constraint(equalToConstant: 20),
            hideButton.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            hideButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            // Collapse button to left of hide
            collapseButton.widthAnchor.constraint(equalToConstant: 20),
            collapseButton.heightAnchor.constraint(equalToConstant: 20),
            collapseButton.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            collapseButton.trailingAnchor.constraint(equalTo: hideButton.leadingAnchor, constant: -4),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        searchBar.placeholder = "Filter"
        searchBar.delegate = self
        searchBar.backgroundImage = UIImage() // remove default border

        // Two-finger double-tap hides the overlay.
        let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissOverlay))
        gesture.numberOfTapsRequired = 2
        gesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(gesture)

        // Subscribe to EventBus log events.
        let logCancellable = EventBus.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case let .log(_, line):
                    self?.append(line: line, color: .green)
                case let .error(msg):
                    self?.append(line: "ERROR: \(msg)", color: .red)
                default:
                    break
                }
            }
        bag.add(logCancellable)
    }

    private func refreshTextView() {
        let filterText = searchBar.text?.lowercased() ?? ""
        let filtered = filterText.isEmpty ? allLines : allLines.filter { $0.string.lowercased().contains(filterText) }
        let combined = NSMutableAttributedString()
        for attr in filtered.suffix(maxLines) { combined.append(attr) }
        textView.attributedText = combined
        textView.scrollRangeToVisible(NSRange(location: textView.text.count - 1, length: 1))
    }

    private func append(line: String, color: UIColor) {
        let attributed = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
        let lineAttr = NSAttributedString(string: line + "\n", attributes: [.foregroundColor: color])
        allLines.append(lineAttr)
        // Trim stored lines
        if allLines.count > 1000 { allLines.removeFirst(allLines.count - 1000) }
        attributed.append(lineAttr)
        // Trim lines if exceeding limit
        refreshTextView()
    }

    @objc private func dismissOverlay() {
        view.removeFromSuperview()
        self.removeFromParent()
    }

    @objc private func clearLogs() {
        textView.attributedText = NSAttributedString()
        allLines.removeAll()
        refreshTextView()
    }

    // MARK: – UISearchBarDelegate
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // ensure searchBar remains first responder state off
    }

    // MARK: – Installation helper
    static func install() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        let overlay = LogOverlayViewController()
        overlay.view.frame = CGRect(x: 8, y: window.safeAreaInsets.top + 8, width: window.bounds.width * 0.48, height: window.bounds.height * 0.3)
        overlay.view.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        window.addSubview(overlay.view)
    }

    // MARK: – Collapse handling
    private var isCollapsed: Bool = false

    @objc private func toggleCollapse() {
        isCollapsed.toggle()
        let arrow = isCollapsed ? "▲" : "▼"
        collapseButton.setTitle(arrow, for: .normal)

        UIView.animate(withDuration: 0.25) {
            self.textView.alpha = self.isCollapsed ? 0.0 : 1.0
        }
    }
}

extension LogOverlayViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        refreshTextView()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        refreshTextView()
    }
}
#endif

