//
//  TextInputViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

/// Protocol for text input completion delegation
protocol TextInputViewControllerDelegate: AnyObject {
    func textInputViewController(_ controller: TextInputViewController, didEnterText text: String)
    func textInputViewControllerDidCancel(_ controller: TextInputViewController)
}

/// Modal view controller for keyboard-based text search input
/// Features large accessible buttons at top, title, clear history button, reversed recent searches list, and input field at bottom
class TextInputViewController: BaseViewController {
    // MARK: - UI Elements
    
    /// Header
    private let buttonsContainer: UIView = {
        let view = UIView()
        view.backgroundColor =  .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let upperButtonsContainer: UIView = {
        let view = UIView()
        view.backgroundColor =  .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let searchButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(R.string.textInput.placeholder(), for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 10
        button.isEnabled = false
        button.accessibilityLabel = R.string.textInput.accessibilitySearch()
        button.accessibilityHint = R.string.textInput.accessibilitySearchHint()
        button.accessibilityTraits = [.button]
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(R.string.textInput.close(), for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 10
        button.accessibilityHint = R.string.textInput.accessibilityExitHint()
        button.accessibilityTraits = [.button]
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let clearHistoryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(R.string.textInput.clearHistory(), for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 10
        button.accessibilityLabel = R.string.textInput.accessibilityClearHistory()
        button.accessibilityHint = R.string.textInput.accessibilityClearHistoryHint()
        button.accessibilityTraits = [.button]
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    /// Search text history list
    private let tableView: UITableView = {
        let table = UITableView()
        table.register(UITableViewCell.self, forCellReuseIdentifier: "RecentSearchCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    /// Search bar for input text to search
    private let searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.searchBarStyle = .default
        bar.placeholder = R.string.textInput.placeholder()
        bar.searchTextField.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        bar.searchTextField.borderStyle = .roundedRect
        // TODO bar.searchTextField.autocapitalizationType = .allCharacters
        bar.backgroundImage = UIImage()
        bar.autocorrectionType = .no
        bar.spellCheckingType = .no
        bar.autocapitalizationType = .none
        bar.tintColor = .systemBlue
        bar.translatesAutoresizingMaskIntoConstraints = false
        
        bar.accessibilityLabel = R.string.textInput.accessibilitySearchField()
        bar.accessibilityHint = R.string.textInput.accessibilitySearchFieldHint()
        bar.accessibilityTraits = .searchField
        return bar
    }()
    
    // MARK: - Properties
    
    weak var delegate: TextInputViewControllerDelegate?
    
    /// Recent search properties
    private let recentSearchesService = RecentTextSearchesService.shared
    private var recentSearches: [String] = []
    private let recentSearchesSubject = CurrentValueSubject<[String], Never>([])
    private var keyboardConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        
        setupUI()
        setupConstraints()
        loadRecentSearches()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        searchBar.becomeFirstResponder()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        announce(text: R.string.textInput.title())
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Re-calculate insets every time the view lays out (orientation change, keyboard appearance, etc.)
        layoutTableToShowLatestEntry()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {        
        view.addSubview(buttonsContainer)
        buttonsContainer.addSubview(upperButtonsContainer)
        upperButtonsContainer.addSubview(searchButton)
        upperButtonsContainer.addSubview(closeButton)
        buttonsContainer.addSubview(clearHistoryButton)
        view.addSubview(tableView)
        view.addSubview(searchBar)
        
        // Set search bar delegate
        searchBar.delegate = self
        
        searchButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.searchTapped() }
            .store(in: &bag)
        
        closeButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.closeTapped() }
            .store(in: &bag)
        
        clearHistoryButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in self?.clearHistoryTapped() }
            .store(in: &bag)
        
        tableView.dataSource = self
        tableView.delegate = self
        
        recentSearchesSubject
            .map { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] hasSearches in
                guard let self else { return }
                self.clearHistoryButton.isEnabled = hasSearches
                self.tableView.isHidden = !hasSearches
            }
            .store(in: &bag)
        
        searchBar.searchTextField
            .textPublisher
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] hasContent in
                guard let self else { return }
                // Update enabled state
                self.searchButton.isEnabled = hasContent
                // Update visible title based on state
                let title = hasContent ? R.string.textInput.searchButton() : R.string.textInput.placeholder()
                self.searchButton.setTitle(title, for: .normal)
            }
            .store(in: &bag)
    }
    
    // MARK: - Constraints
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            buttonsContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            buttonsContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            buttonsContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            {
                let c = buttonsContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
                c.priority = .defaultHigh
                return c
            }()
        ])
        
        NSLayoutConstraint.activate([
            upperButtonsContainer.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            upperButtonsContainer.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor),
            upperButtonsContainer.trailingAnchor.constraint(equalTo: buttonsContainer.trailingAnchor),
            upperButtonsContainer.bottomAnchor.constraint(equalTo: buttonsContainer.centerYAnchor)
        ])
        
        NSLayoutConstraint.activate([
            searchButton.leadingAnchor.constraint(equalTo: upperButtonsContainer.leadingAnchor, constant: 6),
            searchButton.trailingAnchor.constraint(equalTo: upperButtonsContainer.centerXAnchor, constant: -3),
            searchButton.topAnchor.constraint(equalTo: upperButtonsContainer.topAnchor, constant: 6),
            {
                let c = searchButton.bottomAnchor.constraint(equalTo: upperButtonsContainer.bottomAnchor, constant: -3)
                c.priority = .defaultHigh // lower priority to avoid conflict on dismissal
                return c
            }()
        ])
        
        
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: upperButtonsContainer.centerXAnchor, constant: 3),
            closeButton.trailingAnchor.constraint(equalTo: upperButtonsContainer.trailingAnchor, constant: -6),
            closeButton.topAnchor.constraint(equalTo: upperButtonsContainer.topAnchor, constant: 6),
            {
                let c = closeButton.bottomAnchor.constraint(equalTo: upperButtonsContainer.bottomAnchor, constant: -3)
                c.priority = .defaultHigh // lower priority to match searchButton
                return c
            }()
        ])
        
        NSLayoutConstraint.activate([
            clearHistoryButton.topAnchor.constraint(equalTo: buttonsContainer.centerYAnchor, constant: 3),
            clearHistoryButton.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor, constant: 6),
            clearHistoryButton.trailingAnchor.constraint(equalTo: buttonsContainer.trailingAnchor, constant: -6),
            {
                let c = clearHistoryButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor, constant: -6)
                c.priority = .defaultHigh // lower priority to match searchButton
                return c
            }()

        ])
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: tableView.bottomAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        
        keyboardConstraint = searchBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        keyboardConstraint?.isActive = true
    }
    
    // MARK: - Table View Data Source
    private func loadRecentSearches() {
        // Load and reverse the order so most recent appears at bottom (closest to input field)
        let originalSearches = recentSearchesService.getRecentSearches()
        recentSearches = Array(originalSearches.reversed())
        
        // Propagate the mutation so the UI reacts via Combine bindings.
        recentSearchesSubject.send(recentSearches)
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            self.layoutTableToShowLatestEntry()
        }
    }
    
    // MARK: - Layout Helpers
    /// Ensures that the latest (bottom-most) entry is visible and aligned right above the search bar.
    private func layoutTableToShowLatestEntry() {
        // Force the table to calculate its contentSize before we tweak the insets.
        tableView.layoutIfNeeded()
        adjustTableContentInset()
        scrollToBottom()
    }
    
    /// Adds a dynamic top inset so that, when there are only a few rows, they are pinned to the bottom of the list (next to the search bar).
    private func adjustTableContentInset() {
        let tableHeight = tableView.bounds.height
        let contentHeight = tableView.contentSize.height
        
        // If content is shorter than the available space, push it down by increasing the top inset.
        let topInset = max(0, tableHeight - contentHeight)
        tableView.contentInset.top = topInset
    }
    
    /// Scrolls to the newest entry (last row) if it is not already fully visible.
    private func scrollToBottom() {
        guard recentSearches.count > 0 else { return }
        let lastRow = recentSearches.count - 1
        let indexPath = IndexPath(row: lastRow, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
    }
    
    // MARK: - Actions
    
    @objc private func searchTapped() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        performSearch()
    }
    
    @objc private func closeTapped() {
        delegate?.textInputViewControllerDidCancel(self)
        performDismiss()
    }
    
    @objc private func clearHistoryTapped() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        let alert = UIAlertController(
            title: R.string.textInput.clearHistoryConfirmTitle(),
            message: R.string.textInput.clearHistoryConfirmMessage(),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(
            title: R.string.textInput.commonCancel(),
            style: .cancel
        ))
        
        alert.addAction(UIAlertAction(
            title: R.string.textInput.clearHistory(),
            style: .destructive
        ) { [weak self] _ in
            self?.recentSearchesService.clearRecentSearches()
            self?.loadRecentSearches()
            
            let message = R.string.textInput.accessibilityHistoryCleared()
            UIAccessibility.post(notification: .announcement, argument: message)
        })
        
        present(alert, animated: true)
    }
    
    private func performSearch() {
        guard let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !text.isEmpty else { return }

        delegate?.textInputViewController(self, didEnterText: text)
        performDismiss()
    }
    
    private func performDismiss() {
        keyboardConstraint?.isActive = false
        
        let safeAreaConstraint = searchBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        safeAreaConstraint.isActive = true
        
        view.layoutIfNeeded()
        
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource
extension TextInputViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return recentSearches.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RecentSearchCell", for: indexPath)
        
        let searchText = recentSearches[indexPath.row]
        cell.textLabel?.text = searchText.uppercased()
        cell.textLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        cell.accessoryType = .none
        cell.selectionStyle = .default
        
        // Add search icon
        let searchImage = UIImage(systemName: "clock.arrow.circlepath")
        cell.imageView?.image = searchImage
        cell.imageView?.tintColor = .systemBlue
        
        // Accessibility
        cell.accessibilityLabel = R.string.textInput.accessibilityRecentSearch(searchText)
        cell.accessibilityHint = R.string.textInput.accessibilityRecentSearchHint()
        
        // Debug: Cell creation
        print("TextInputViewController: Creating cell for row \(indexPath.row) with text: '\(searchText)'")
        
        return cell
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
    
    private func notifyVoiceOverOfScrollPosition() {
        let totalItems = tableView.numberOfRows(inSection: 0)
        
        var message = R.string.itemList.accessibilityEmptyList()
        
        if totalItems != 0 {
            guard let visibleRows = tableView.indexPathsForVisibleRows?.sorted(),
                  !visibleRows.isEmpty else { return }
            let firstVisible = (visibleRows.first?.row ?? 0) + 1
            message = R.string.itemList.accessibilityScrollStatus(firstVisible, totalItems)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIAccessibility.post(notification: .pageScrolled, argument: message)
        }
    }
}

// MARK: - UITableViewDelegate
extension TextInputViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedText = recentSearches[indexPath.row]
        searchBar.text = selectedText
        searchButton.isEnabled = !selectedText.isEmpty
        
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
        
        announce(text: selectedText)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let searchText = recentSearches[indexPath.row]
            
            // Remove from service
            recentSearchesService.removeRecentSearch(searchText)
            
            // Update local array
            recentSearches.remove(at: indexPath.row)
            
            // Update UI
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            // Re-adjust layout so the remaining rows stay anchored to the bottom.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.layoutTableToShowLatestEntry()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return R.string.textInput.commonDelete()
    }
}

extension TextInputViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard !text.isEmpty else {
            hapticFeedbackManager.playPattern(.continuous, intensity: Constants.hapticButtonIntensity)
            return
        }
        
        performSearch()
        performDismiss()
    }
}

