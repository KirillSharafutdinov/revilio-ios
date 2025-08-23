//
//  ItemListViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

/// Protocol for handling item selection from the list
protocol ItemListViewControllerDelegate: AnyObject {
    func itemListViewController(_ controller: ItemListViewController, didSelectItem item: ItemDisplayInfo)
    func itemListViewControllerDidCancel(_ controller: ItemListViewController)
    
}

/// View controller that displays a searchable list of available items for object search
class ItemListViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {
 
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
        label.text = R.string.itemList.title()
        label.font = UIFont.boldSystemFont(ofSize: 28)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.accessibilityLabel = R.string.itemList.title()
        label.accessibilityHint = R.string.itemList.accessibilityTitleHint()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        // Configure title directly so that AccessibilityStyle can capture it before styling.
        button.setTitle(R.string.textInput.close(), for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 10
        // Accessibility
        button.accessibilityHint = R.string.itemList.accessibilityCloseHint()
        button.accessibilityTraits = [.button]
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    /// Items list
    private let tableView: UITableView = {
        let table = UITableView()
        table.register(UITableViewCell.self, forCellReuseIdentifier: "ItemCell")
        table.accessibilityLabel = R.string.itemList.accessibilityItemsList()
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    /// Search bar for filtering items
    private let searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.searchBarStyle = .default
        bar.placeholder = R.string.itemList.searchPlaceholder()
        bar.searchTextField.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        bar.searchTextField.borderStyle = .roundedRect
        bar.autocorrectionType = .no
        bar.spellCheckingType = .no
        bar.autocapitalizationType = .none
        bar.tintColor = .systemBlue
        bar.accessibilityLabel = R.string.itemList.accessibilitySearchField()
        bar.accessibilityHint = R.string.itemList.accessibilitySearchFieldHint()
        bar.accessibilityTraits = .searchField
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()
    
    // MARK: - Properties
    /// Delegate for handling item selection
    weak var delegate: ItemListViewControllerDelegate?
    /// All available items, flattened and sorted alphabetically
    private var allItems: [ItemDisplayInfo] = []
    /// Filtered items for search results  
    private var filteredItems: [ItemDisplayInfo] = []
    /// Tracks whether the controller is in the process of dismissing
    private var keyboardConstraint: NSLayoutConstraint?

    // MARK: - Initialization
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Opt-in to adaptive button background (white in dark mode / black in light, alpha 0.7)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        
        setupUI()
        setupConstraints()
        loadItems()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.main.async {
            self.searchBar.becomeFirstResponder()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        announce(text: R.string.itemList.title())
    }
    
    // MARK: - UI Setup
 
    private func setupUI() {
        view.addSubview(topContainer)
        topContainer.addSubview(titleLabel)
        topContainer.addSubview(closeButton)
        view.addSubview(tableView)
        view.addSubview(searchBar)
        
        let closeC = closeButton
            .publisher(for: .touchUpInside)
            .sink { [weak self] _ in
                self?.closeTapped()
            }
        bag.add(closeC)
        
        tableView.dataSource = self
        tableView.delegate = self
        
        let searchC = searchBar.searchTextField
            .textPublisher
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.filterItems(for: text)
            }
        bag.add(searchC)
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
            tableView.topAnchor.constraint(equalTo: topContainer.bottomAnchor),
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
    
    private func loadItems() {
        let modelGroups = ItemsForSearchRegistryService.shared.getItemsGroupedByModel()
        allItems = modelGroups.flatMap { $0.items }.sorted { $0.displayName < $1.displayName }
        filteredItems = allItems
        
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredItems.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // No more section headers are needed.
        return nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
        
        // Protect against out-of-bounds if data changed after async reload
        guard indexPath.row < filteredItems.count else { return cell }
        
        let item = filteredItems[indexPath.row]
        
        // Configure cell content
        cell.textLabel?.text = item.displayName.uppercased()
        cell.textLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        
        // Show alternative names if available
        if !item.alternativeNames.isEmpty {
            cell.detailTextLabel?.text = item.alternativeNames.joined(separator: ", ")
            cell.detailTextLabel?.font = .systemFont(ofSize: 14)
            cell.detailTextLabel?.textColor = .secondaryLabel
        } else {
            cell.detailTextLabel?.text = nil
        }
        
        // Configure cell appearance
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        
        cell.accessibilityLabel = item.displayName
        cell.accessibilityTraits = .button
        
        return cell
        
        
    }
    
    // MARK: - Table View Delegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard indexPath.row < filteredItems.count else { return }
        let selectedItem = filteredItems[indexPath.row]
        
        // Notify delegate and dismiss
        delegate?.itemListViewController(self, didSelectItem: selectedItem)
        performDismiss()
    }
    
    // MARK: - Search Filtering
    
    private func filterItems(for searchText: String) {
        // Do not perform filtering if the controller is being dismissed

        let normalizedSearchText = searchText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let previousItemCount = filteredItems.count

        if normalizedSearchText.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter { item in
                // Search in display name (case-insensitive)
                if item.displayName.lowercased().contains(normalizedSearchText) {
                    return true
                }
                
                // Search in English class name (for advanced users)
                if item.classNameInModel.lowercased().contains(normalizedSearchText) {
                    return true
                }
                
                return false
            }
        }
        
        // Play a haptic signal if the list just became empty
        if previousItemCount > 0 && filteredItems.isEmpty {
            hapticFeedbackManager.playPattern(.continuous, intensity: 0.7)
        }

        // Auto-select and dismiss if only one item remains
        if filteredItems.count == 1 && previousItemCount > 1 {
            if let item = filteredItems.first {
                delegate?.itemListViewController(self, didSelectItem: item)
                performDismiss()
                return
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
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
    
    // MARK: - Actions
    
    @objc private func closeTapped() {
        delegate?.itemListViewControllerDidCancel(self)
        performDismiss()
    }
    
    private func performDismiss() {
        keyboardConstraint?.isActive = false
        searchBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        
        view.layoutIfNeeded()
        
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
                
        dismiss(animated: true)
    }
}

