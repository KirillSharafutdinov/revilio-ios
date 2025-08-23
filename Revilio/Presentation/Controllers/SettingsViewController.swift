//
//  SettingsViewController.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit
import Combine

/// A lightweight placeholder implementation for the settings screen.
/// The view is intentionally simple so that it is easy to extend later.
/// All strings are currently Russian to match the rest of the UI.
class SettingsViewController: BaseTableViewController, ModalDismissDelegate {
    
    // MARK: - IBOutlets
    
    // Section 0 – General
    @IBOutlet private weak var languageValueLabel: UILabel!
    @IBOutlet private weak var languageMainLabel: UILabel!
    
    @IBOutlet private weak var audioRouteLabel: UILabel!
    @IBOutlet private weak var audioRouteSegmented: UISegmentedControl!
    
    @IBOutlet private weak var trainingMenuOnOffLabel: UILabel!
    @IBOutlet private weak var trainingMenuOnOffSegmented: UISegmentedControl!
    
    // Section 1 – Item search options
    @IBOutlet private weak var itemSelectMethodLabel: UILabel!
    @IBOutlet private weak var itemInputMethodSegmented: UISegmentedControl!
    
    @IBOutlet weak var itemSearchFlashlightLabel: UILabel!
    @IBOutlet weak var itemSearchFlashlightSegmented: UISegmentedControl!
    
    @IBOutlet private weak var itemSearchFeedbackLabel: UILabel!
    @IBOutlet private weak var objFeedbackSegmented: UISegmentedControl!
    
    @IBOutlet weak var itemSearchAutooffLabel: UILabel!
    @IBOutlet weak var itemSearchAutooffSegmented: UISegmentedControl!
    
    // Section 2 – Text search options
    @IBOutlet private weak var textInputMethodLabel: UILabel!
    @IBOutlet private weak var textInputMethodSegmented: UISegmentedControl!
    
    @IBOutlet private weak var textSearchFlashlightLabel: UILabel!
    @IBOutlet private weak var textSearchFlashlightSegmented: UISegmentedControl!
    
    @IBOutlet private weak var textSearchFeedbackLabel: UILabel!
    @IBOutlet private weak var textSearchFeedbackSegmented: UISegmentedControl!
    
    @IBOutlet weak var textSearchAutooffLabel: UILabel!
    @IBOutlet weak var textSearchAutooffSegmented: UISegmentedControl!
    
    @IBOutlet weak var clearHistoryLabel: UILabel!
    
    // Section 3 – Text reading options
    @IBOutlet weak var textReadingMethodLabel: UILabel!
    @IBOutlet weak var textReadingMethodSegmented: UISegmentedControl!
    
    @IBOutlet weak var textReadingFlashlightLabel: UILabel!
    @IBOutlet weak var textReadingFlashlightSegmented: UISegmentedControl!
    
    @IBOutlet weak var textReadingNavigationLabel: UILabel!
    @IBOutlet weak var textReadingNavigationSegmented: UISegmentedControl!
    
    // Section 4 – About
    @IBOutlet private weak var aboutLabel: UILabel!
    
    // Section 5 – Reset to Defaults
    @IBOutlet private weak var resetToDefaultsLabel: UILabel!
    
    // MARK: - Private Properties
    
    private var languageChangedFlag = false
    
    // MARK: - UserDefaults Properties
    private enum DefaultsKey: String {
        case trainingMenuEnabled   = "settings.trainingMenuEnabled"
        
        case itemInputMethod       = "settings.itemInputMethod"
        case objFeedbackType       = "settings.objFeedbackType"
        case itemSearchFlashlight  = "settings.itemSearchFlashlight"
        case itemSearchAutooff     = "settings.itemSearchAutooff"
        
        case textInputMethod       = "settings.textInputMethod"
        case textSearchFlashlight  = "settings.textSearchFlashlight"
        case textFeedbackType      = "settings.textFeedbackType"
        case textSearchAutooff     = "settings.textSearchAutooff"
        
        case textReadingMethod     = "settings.textReadingMethod"
        case textReadingFlashlight = "settings.textReadingFlashlight"
        case textReadingNavigation = "settings.textReadingNavigation"
    }

    /// Centralised map of default values used both for registration and for hard reset.
    static let defaultUserDefaults: [String: Any] = [
        DefaultsKey.trainingMenuEnabled.rawValue: 1, // enabled

        DefaultsKey.itemInputMethod.rawValue: ItemInputMethod.voice.rawValue,
        DefaultsKey.itemSearchFlashlight.rawValue: 0, // disabled
        DefaultsKey.objFeedbackType.rawValue: FeedbackType.both.rawValue,
        DefaultsKey.itemSearchAutooff.rawValue: 1, // 2 minutes
        
        DefaultsKey.textInputMethod.rawValue: TextInputMethod.voice.rawValue,
        DefaultsKey.textSearchFlashlight.rawValue: 0, // disabled
        DefaultsKey.textFeedbackType.rawValue: FeedbackType.both.rawValue,
        DefaultsKey.textSearchAutooff.rawValue: 1, // 2 minutes
        
        DefaultsKey.textReadingMethod.rawValue: 1, // page mode (central cluster filtering)
        DefaultsKey.textReadingFlashlight.rawValue: 0, // disabled
        DefaultsKey.textReadingNavigation.rawValue: 1 // sentences
    ]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        tableView.rowHeight = 60

        registerDefaultSettings()
        
        configureNavigation()

        syncUIFromCurrentSettings()

        let pairs: [(UISegmentedControl?, (UISegmentedControl) -> Void, UIControl.Event)] = [
            (audioRouteSegmented,        { [weak self] ctl in self?.audioRouteChanged(ctl) }, .valueChanged),
            (trainingMenuOnOffSegmented, { [weak self] ctl in self?.trainingMenuOnOffChanged(ctl) }, .valueChanged),
            (itemSearchFlashlightSegmented, { [weak self] ctl in self?.itemSearchFlashlightChanged(ctl) }, .valueChanged),
            (textSearchFlashlightSegmented, { [weak self] ctl in self?.textSearchFlashlightChanged(ctl) }, .valueChanged),
            (textReadingMethodSegmented, { [weak self] ctl in self?.textReadingMethodChanged(ctl) }, .valueChanged),
            (textReadingFlashlightSegmented, { [weak self] ctl in self?.textReadingFlashlightChanged(ctl) }, .valueChanged),
            (textReadingNavigationSegmented, { [weak self] ctl in self?.textReadingNavigationChanged(ctl) }, .valueChanged),
            (itemInputMethodSegmented,   { [weak self] ctl in self?.itemSelectMethodChanged(ctl) }, .valueChanged),
            (objFeedbackSegmented,       { [weak self] ctl in self?.itemSearchFeedbackChanged(ctl) }, .valueChanged),
            (textInputMethodSegmented,   { [weak self] ctl in self?.textInputMethodChanged(ctl) }, .valueChanged),
            (textSearchFeedbackSegmented,{ [weak self] ctl in self?.textSearchFeedbackChanged(ctl) }, .valueChanged),
            (itemSearchAutooffSegmented, { [weak self] ctl in self?.itemSearchAutooffChanged(ctl) }, .valueChanged),
            (textSearchAutooffSegmented, { [weak self] ctl in self?.textSearchAutooffChanged(ctl) }, .valueChanged)
        ]
        for (seg, handler, evt) in pairs {
            guard let seg = seg else { continue }
            seg.removeTarget(nil, action: nil, for: evt)
            seg.publisher(for: evt)
                .compactMap { $0 as? UISegmentedControl }
                .sink(receiveValue: handler)
                .store(in: &bag)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncUIFromCurrentSettings()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        announce(text: R.string.settings.title())
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        speechSynthesizer.stopSpeaking()
    }
    
    // MARK: - Public Methods
    
    /// Get the current object search feedback type
    func getObjectSearchFeedbackType() -> FeedbackType {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.objFeedbackType.rawValue) as? Int ?? FeedbackType.both.rawValue
        return FeedbackType(rawValue: index) ?? .both
    }
    
    /// Get the current text search feedback type
    func getTextSearchFeedbackType() -> FeedbackType {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.textFeedbackType.rawValue) as? Int ?? FeedbackType.both.rawValue
        return FeedbackType(rawValue: index) ?? .both
    }
    
    /// Get the current item input method
    func getItemInputMethod() -> ItemInputMethod {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.itemInputMethod.rawValue) as? Int ?? ItemInputMethod.voice.rawValue
        return ItemInputMethod(rawValue: index) ?? .voice
    }
    
    /// Get the current text input method
    func getTextInputMethod() -> TextInputMethod {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.textInputMethod.rawValue) as? Int ?? TextInputMethod.voice.rawValue
        return TextInputMethod(rawValue: index) ?? .voice
    }
    
    /// Get whether training menu is enabled
    func isTrainingMenuEnabled() -> Bool {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.trainingMenuEnabled.rawValue) as? Int ?? 0
        return index == 1
    }
    
    /// Get whether item search flashlight is enabled
    func isItemSearchFlashlightEnabled() -> Bool {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.itemSearchFlashlight.rawValue) as? Int ?? 0
        return index == 1
    }
    
    /// Get whether text search flashlight is enabled
    func isTextSearchFlashlightEnabled() -> Bool {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.textSearchFlashlight.rawValue) as? Int ?? 0
        return index == 1
    }
    
    /// Get whether text reading flashlight is enabled
    func isTextReadingFlashlightEnabled() -> Bool {
        let index = UserDefaults.standard.object(forKey: DefaultsKey.textReadingFlashlight.rawValue) as? Int ?? 0
        return index == 1
    }
    
    /// Get the current text reading method
    func getTextReadingMethod() -> Int {
        return UserDefaults.standard.object(forKey: DefaultsKey.textReadingMethod.rawValue) as? Int ?? 0
    }
    
    /// Get the current text navigation method
    func getTextReadingNavigation() -> Int {
        return UserDefaults.standard.object(forKey: DefaultsKey.textReadingNavigation.rawValue) as? Int ?? 0
    }
    
    // MARK: - Actions
    
    @IBAction private func audioRouteChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        let newRoute: AudioOutputRoute = (sender.selectedSegmentIndex == 0) ? .receiver : .speaker

        speechSynthesizer.setAudioOutputRoute(newRoute)

        announceSettingChange(for: sender)
    }

    @IBAction private func trainingMenuOnOffChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        let enabled = sender.selectedSegmentIndex == 1
        SettingsManager.shared.setTrainingMenuEnabled(enabled)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func itemSearchFlashlightChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.itemSearchFlashlight.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func textSearchFlashlightChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textSearchFlashlight.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func textReadingMethodChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textReadingMethod.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func textReadingFlashlightChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textReadingFlashlight.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func textReadingNavigationChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textReadingNavigation.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func itemSelectMethodChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.itemInputMethod.rawValue)
        announceSettingChange(for: sender)
    }

    @IBAction private func itemSearchFeedbackChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.objFeedbackType.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction func itemSearchAutooffChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.itemSearchAutooff.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction private func textInputMethodChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textInputMethod.rawValue)
        announceSettingChange(for: sender)
    }
 
    @IBAction private func textSearchFeedbackChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textFeedbackType.rawValue)
        announceSettingChange(for: sender)
    }
    
    @IBAction func textSearchAutooffChanged(_ sender: UISegmentedControl) {
        playTapHaptic()
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: DefaultsKey.textSearchAutooff.rawValue)
        announceSettingChange(for: sender)
    }

    /// Triggered from the storyboard Language row (primaryAction) to open picker.
    @IBAction private func languageCellTapped(_ sender: Any) {
        playTapHaptic()
        presentLanguagePicker()
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - UI Configuration
    
    private func registerDefaultSettings() {
        let defaults = UserDefaults.standard
        
        defaults.register(defaults: Self.defaultUserDefaults)
    }

    private func configureNavigation() {
        title = R.string.settings.title()
        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close,
                                                            target: self,
                                                            action: #selector(closeTapped))
    }
    
    /// Updates all UI labels with localized strings
    internal override func updateTexts() {
        tableView.accessibilityLabel = R.string.settings.tableViewLabel()
        tableView.accessibilityHint = R.string.settings.swipeToScroll()
        
        // 0 - General
        languageMainLabel?.text = R.string.settings.languageLabel()
        languageMainLabel?.accessibilityHint = R.string.settings.languageHint()
        
        audioRouteLabel?.text = R.string.settings.itemSoundSource()
        audioRouteSegmented?.setTitle(R.string.settings.audioRouteQuiet(), forSegmentAt: 0)
        audioRouteSegmented?.setTitle(R.string.settings.audioRouteLoud(), forSegmentAt: 1)
        audioRouteSegmented?.accessibilityLabel = R.string.settings.itemSoundSource()
        
        trainingMenuOnOffLabel?.text = R.string.settings.trainingMenuLabel()
        trainingMenuOnOffSegmented?.setTitle(R.string.settings.switchOff(), forSegmentAt: 0)
        trainingMenuOnOffSegmented?.setTitle(R.string.settings.switchOn(), forSegmentAt: 1)
        trainingMenuOnOffSegmented?.accessibilityLabel = R.string.settings.trainingMenuLabel()
        
        // 1 - Object search
        itemSelectMethodLabel?.text = R.string.settings.itemInputMethodLabel()
        for (index, inputMethod) in ItemInputMethod.allCases.enumerated() {
            itemInputMethodSegmented?.setTitle(inputMethod.localizedDescription, forSegmentAt: index)
        }
        itemInputMethodSegmented?.accessibilityLabel = R.string.settings.itemInputMethodLabel()
        
        itemSearchFlashlightLabel?.text = R.string.settings.itemSearchFlashlight()
        for seg in [itemSearchFlashlightSegmented, textSearchFlashlightSegmented, textReadingFlashlightSegmented] {
            seg?.setTitle(R.string.settings.switchOff(), forSegmentAt: 0)
            seg?.setTitle(R.string.settings.switchOn(), forSegmentAt: 1)
        }
        itemSearchFlashlightSegmented?.accessibilityLabel = R.string.settings.itemSearchFlashlight()
        
        itemSearchFeedbackLabel?.text = R.string.settings.itemFeedback()
        for (index, feedbackType) in FeedbackType.allCases.enumerated() {
            objFeedbackSegmented?.setTitle(feedbackType.localizedDescription, forSegmentAt: index)
            textSearchFeedbackSegmented?.setTitle(feedbackType.localizedDescription, forSegmentAt: index)
        }
        objFeedbackSegmented?.accessibilityLabel = R.string.settings.itemFeedback()
        
        itemSearchAutooffLabel?.text = R.string.settings.itemSearchAutooff()
        for seg in [itemSearchAutooffSegmented, textSearchAutooffSegmented] {
            seg?.setTitle(R.string.settings.autooffOff(), forSegmentAt: 0)
            seg?.setTitle(R.string.settings.autooff2min(), forSegmentAt: 1)
            seg?.setTitle(R.string.settings.autooff5min(), forSegmentAt: 2)
        }
        itemSearchAutooffSegmented?.accessibilityLabel = R.string.settings.itemSearchAutooff()
        
        // 2 - Text Search
        textInputMethodLabel?.text = R.string.settings.textInputMethodLabel()
        for (index, inputMethod) in TextInputMethod.allCases.enumerated() {
            textInputMethodSegmented?.setTitle(inputMethod.localizedDescription, forSegmentAt: index)
        }
        textInputMethodSegmented?.accessibilityLabel = R.string.settings.textInputMethodLabel()
        
        textSearchFlashlightLabel?.text = R.string.settings.textSearchFlashlight()
        textSearchFlashlightSegmented?.accessibilityLabel = R.string.settings.textSearchFlashlight()
        
        textSearchFeedbackLabel?.text = R.string.settings.textFeedback()
        textSearchFeedbackSegmented?.accessibilityLabel = R.string.settings.textFeedback()
        
        textSearchAutooffLabel?.text = R.string.settings.textSearchAutooff()
        textSearchAutooffSegmented?.accessibilityLabel = R.string.settings.textSearchAutooff()
        
        clearHistoryLabel?.text = R.string.settings.textSearchClearHistory()
        
        // 3 - Text Reading
        textReadingMethodLabel?.text = R.string.settings.textReadingArea()
        textReadingMethodSegmented?.setTitle(R.string.settings.readingWholeFrame(), forSegmentAt: 0)
        textReadingMethodSegmented?.setTitle(R.string.settings.readingPage(), forSegmentAt: 1)
        textReadingMethodSegmented?.accessibilityLabel = R.string.settings.textReadingArea()
           
        textReadingFlashlightLabel?.text = R.string.settings.textReadingFlashlight()
        textReadingFlashlightSegmented?.accessibilityLabel = R.string.settings.textReadingFlashlight()
        
        textReadingNavigationLabel?.text = R.string.settings.readingNavigation()
        textReadingNavigationSegmented?.setTitle(R.string.settings.readingNavigationLines(), forSegmentAt: 0)
        textReadingNavigationSegmented?.setTitle(R.string.settings.readingNavigationSentences(), forSegmentAt: 1)
        textReadingNavigationSegmented?.accessibilityLabel = R.string.settings.readingNavigation()
        
        // 3 - About
        aboutLabel?.text = R.string.settings.aboutTitle()
        
        // 4 - Reset
        resetToDefaultsLabel?.text = R.string.settings.resetTitle()
    }

    // MARK: - Initial UI synchronisation

    private func syncUIFromCurrentSettings() {
        // Language display
        languageValueLabel.text = localizedLanguageName(for: LocalizationManager.shared.currentLanguage)

        let defaults = UserDefaults.standard
        
        // Audio route – always reflect the setting from the shared synthesizer
        audioRouteSegmented.selectedSegmentIndex = (speechSynthesizer.audioOutputRoute == .receiver) ? 0 : 1
        
        // Training menu on/off (default to off which is index 0)
        let trainingMenuIndex = defaults.object(forKey: DefaultsKey.trainingMenuEnabled.rawValue) as? Int ?? 0
        trainingMenuOnOffSegmented.selectedSegmentIndex = trainingMenuIndex
        
        // Pull feedback types from UserDefaults (default to .both which is index 2)
        let objFeedbackIndex = defaults.object(forKey: DefaultsKey.objFeedbackType.rawValue) as? Int ?? FeedbackType.both.rawValue
        let textFeedbackIndex = defaults.object(forKey: DefaultsKey.textFeedbackType.rawValue) as? Int ?? FeedbackType.both.rawValue
        
        objFeedbackSegmented.selectedSegmentIndex = objFeedbackIndex
        textSearchFeedbackSegmented.selectedSegmentIndex = textFeedbackIndex
        
        // Pull item input method from UserDefaults (default to .voice which is index 0)
        let itemInputMethodIndex = defaults.object(forKey: DefaultsKey.itemInputMethod.rawValue) as? Int ?? ItemInputMethod.voice.rawValue
        itemInputMethodSegmented.selectedSegmentIndex = itemInputMethodIndex
        
        // Pull text input method from UserDefaults (default to .voice which is index 0)
        let textInputMethodIndex = defaults.object(forKey: DefaultsKey.textInputMethod.rawValue) as? Int ?? TextInputMethod.voice.rawValue
        textInputMethodSegmented.selectedSegmentIndex = textInputMethodIndex
        
        // Pull flashlight settings from UserDefaults (default to off which is index 0)
        let itemSearchFlashlightIndex = defaults.object(forKey: DefaultsKey.itemSearchFlashlight.rawValue) as? Int ?? 0
        itemSearchFlashlightSegmented.selectedSegmentIndex = itemSearchFlashlightIndex
        
        let textSearchFlashlightIndex = defaults.object(forKey: DefaultsKey.textSearchFlashlight.rawValue) as? Int ?? 0
        textSearchFlashlightSegmented.selectedSegmentIndex = textSearchFlashlightIndex
        
        let textReadingFlashlightIndex = defaults.object(forKey: DefaultsKey.textReadingFlashlight.rawValue) as? Int ?? 0
        textReadingFlashlightSegmented.selectedSegmentIndex = textReadingFlashlightIndex
        
        // Pull text reading method from UserDefaults (default to first option which is index 0)
        let textReadingMethodIndex = defaults.object(forKey: DefaultsKey.textReadingMethod.rawValue) as? Int ?? 0
        textReadingMethodSegmented.selectedSegmentIndex = textReadingMethodIndex
        
        // Pull text navigation method from UserDefaults (default to second option which is index 1)
        let textReadingNavigationIndex = defaults.object(forKey: DefaultsKey.textReadingNavigation.rawValue) as? Int ?? 1
        textReadingNavigationSegmented.selectedSegmentIndex = textReadingNavigationIndex
        
        // Pull auto-off settings from UserDefaults (default to position 1 which is 2 minutes)
        let itemSearchAutooffIndex = defaults.object(forKey: DefaultsKey.itemSearchAutooff.rawValue) as? Int ?? 1
        itemSearchAutooffSegmented.selectedSegmentIndex = itemSearchAutooffIndex
        
        let textSearchAutooffIndex = defaults.object(forKey: DefaultsKey.textSearchAutooff.rawValue) as? Int ?? 1
        textSearchAutooffSegmented.selectedSegmentIndex = textSearchAutooffIndex
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        // Language picker
        if indexPath.section == 0 && indexPath.row == 0 {
            playTapHaptic()
            presentLanguagePicker()
            return
        }
        
        // Clear text search history
        if indexPath.section == 2 && indexPath.row == 4 {
            playTapHaptic()
            clearHistoryTapped()
            return
        }
        
        // About app cell
        if indexPath.section == 4 && indexPath.row == 0 {
            playTapHaptic()
            aboutTapped()
            return
        }
        
        // Reset settings
        if indexPath.section == 5 && indexPath.row == 0 {
            playTapHaptic()
            resetSettingsTapped(self)
            return
        }
        
        if let labelText = labelForCell(at: indexPath)?.text {
            announce(text: labelText)
        }
    }
    
    private func labelForCell(at indexPath: IndexPath) -> UILabel? {
        switch (indexPath.section, indexPath.row) {
        // Section 0 - General
        case (0, 0): return languageMainLabel
        case (0, 1): return audioRouteLabel
        case (0, 2): return trainingMenuOnOffLabel
            
        // Section 1 - Item search
        case (1, 0): return itemSelectMethodLabel
        case (1, 1): return itemSearchFlashlightLabel
        case (1, 2): return itemSearchFeedbackLabel
        case (1, 3): return itemSearchAutooffLabel
            
        // Section 2 - Text search
        case (2, 0): return textInputMethodLabel
        case (2, 1): return textSearchFlashlightLabel
        case (2, 2): return textSearchFeedbackLabel
        case (2, 3): return textSearchAutooffLabel
            
        // Section 3 - Text reading
        case (3, 0): return textReadingMethodLabel
        case (3, 1): return textReadingFlashlightLabel
        case (3, 2): return textReadingNavigationLabel
            
        default:
            return nil
        }
    }

    /// Provides localized titles for each static section header.
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1:
            return R.string.settings.sectionItems()
        case 2:
            return R.string.settings.sectionText()
        case 3:
            return R.string.settings.sectionReading()
        default:
            return nil
        }
    }

    // MARK: - Language Handling

    /// Presents an action sheet that lets the user choose the app's language.
    private func presentLanguagePicker() {
        self.announce(text: R.string.settings.languagePickerAnnounce())
        
        let alert = UIAlertController(title: R.string.settings.languageSection(),
                                      message: nil,
                                      preferredStyle: .actionSheet)
        
        let currentLanguage = LocalizationManager.shared.currentLanguage
        
        for language in AppLanguage.allCases {
            alert.addAction(UIAlertAction(title: localizedLanguageName(for: language),
                                          style: .default) { _ in
                if language != currentLanguage {
                    self.languageChangedFlag = true
                }
                
                LocalizationManager.shared.set(language: language)
            })
        }
        
        alert.addAction(UIAlertAction(title: R.string.settings.close(), style: .cancel) { _ in
            self.announce(text: self.localizedLanguageName(for: currentLanguage))
        })
        
        // For iPad – action sheet must be anchored
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }

    /// Returns a human-readable display name for the given `AppLanguage`.
    private func localizedLanguageName(for language: AppLanguage) -> String {
        switch language {
        case .ru:     return R.string.settings.languageRu()
        case .en:     return R.string.settings.languageEn()
        case .zhHans: return R.string.settings.languageZhHans()
        }
    }
    
    /// Called whenever the app language has changed. Rebuilds the table contents and updates visible texts.
    @objc internal override func languageChanged() {
        
        // Update all UI elements on the main thread with enhanced error handling
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.configureNavigation()
            
            self.updateTexts()
            
            self.languageValueLabel.text = self.localizedLanguageName(for: LocalizationManager.shared.currentLanguage)
                        
            self.tableView.reloadData()
            
            let headerTitles = [
                "",  // 0 - General
                R.string.settings.sectionItems(),   // 1 - Item search
                R.string.settings.sectionText(),    // 2 - Text search
                R.string.settings.sectionReading(), // 3 - Text reading
                R.string.settings.languageSection(), // 4 - Language
                ""   // 5 - Reset section (no title)
            ]
            for section in 0..<headerTitles.count {
                if let header = self.tableView.headerView(forSection: section) {
                    header.textLabel?.text = headerTitles[section]
                }
            }
            
            self.tableView.setNeedsLayout()
            self.tableView.layoutIfNeeded()
            
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            
            self.updateAccessibilityAfterLanguageChange()
            
            if self.languageChangedFlag {
                if let announcement = self.languageValueLabel.text {
                    self.announce(text: announcement)
                }
                
                self.languageChangedFlag = false
            }
        }
    }
    
    /// Updates accessibility elements after language change
    private func updateAccessibilityAfterLanguageChange() {
        tableView.accessibilityLabel = R.string.settings.title()
        
        tableView.visibleCells.forEach { $0.accessibilityLabel = $0.textLabel?.text }
    }
    
    private func announceSettingChange(for control: UISegmentedControl) {

        let selectedIndex = control.selectedSegmentIndex
        let controlLabel = control.accessibilityLabel ?? R.string.settings.unknownSetting()
        let selectedOption = control.titleForSegment(at: selectedIndex) ?? R.string.settings.unknownOption()
        
        let announcement = R.string.settings.settingChangedAnnouncement(controlLabel, selectedOption)
        
        announce(text: announcement)
    }
    
    // MARK: - UIScrollViewDelegate
    
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyVoiceOverOfScrollPosition()
    }
    
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            notifyVoiceOverOfScrollPosition()
        }
    }
    
    private func notifyVoiceOverOfScrollPosition() {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows, !visibleIndexPaths.isEmpty else { return }
        
        let visibleSections = Set(visibleIndexPaths.map { $0.section })
        
        let firstVisibleSection = visibleSections.min() ?? 0
        
        let totalPagesCount = 2
        
        var thisPageNumber = 2

        if firstVisibleSection == 0 {
            thisPageNumber = 1
        }
        
        let message = R.string.settings.accessibilityScrollStatus(thisPageNumber, totalPagesCount)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIAccessibility.post(notification: .pageScrolled, argument: message)
        }
    }
    
    // MARK: - Haptics
    
    /// Plays a subtle haptic signal for discrete UI interactions.
    private func playTapHaptic() {
        hapticFeedbackManager.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
    }

    // MARK: - Reset to Defaults

    /// Presents confirmation alert and performs full reset if the user agrees.
    private func resetSettingsTapped(_ sender: Any) {
        announce(text: R.string.settings.resetTitle())
        
        let alert = UIAlertController(title: R.string.settings.resetTitle(),
                                      message: R.string.settings.resetMessage(),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: R.string.settings.cancel(), style: .cancel))
        alert.addAction(UIAlertAction(title: R.string.settings.resetConfirm(), style: .destructive) { [weak self] _ in
            self?.performHardReset()
        })
        
        present(alert, animated: true)
    }
    
    private func clearHistoryTapped() {
        let recentSearchesService = RecentTextSearchesService.shared

        playTapHaptic()
        
        announce(text: R.string.textInput.clearHistoryConfirmTitle())

        let alert = UIAlertController(title: R.string.textInput.clearHistoryConfirmTitle(),
                                      message: R.string.textInput.clearHistoryConfirmMessage(),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: R.string.textInput.commonCancel(), style: .cancel))
        alert.addAction(UIAlertAction(title: R.string.textInput.clearHistory(), style: .destructive) {_ in
            recentSearchesService.clearRecentSearches()
            
            let message = R.string.textInput.accessibilityHistoryCleared()
            UIAccessibility.post(notification: .announcement, argument: message)
        })
        
        present(alert, animated: true)
    }

    /// Applies default values, updates dependent singletons and refreshes UI.
    private func performHardReset() {
        let defaults = UserDefaults.standard
        for (key, value) in Self.defaultUserDefaults {
            defaults.set(value, forKey: key)
        }

        speechSynthesizer.setAudioOutputRoute(.speaker)
        
        SettingsManager.shared.setTrainingMenuEnabled(true)

        defaults.synchronize()

        syncUIFromCurrentSettings()

        announce(text: R.string.settings.resetDone())
    }
    
    // MARK: - "About App"
    
    private func aboutTapped() {
        let storyboard = UIStoryboard(name: "About", bundle: nil)
        
        guard let aboutVC = storyboard.instantiateInitialViewController() as? AboutContainerViewController else { return }
        
        aboutVC.modalDismissDelegate = self
        aboutVC.modalPresentationStyle = .fullScreen
        present(aboutVC, animated: true)
    }
    
    func modalDidDismiss() {
        announce(text: R.string.settings.title())
    }
}

// FeedbackType Extension for Localization
extension FeedbackType: CaseIterable {
    public static var allCases: [FeedbackType] {
        return [.haptic, .sound, .both]
    }
    
    var localizedDescription: String {
        switch self {
        case .haptic:
            return R.string.settings.feedbackHaptic()
        case .sound:
            return R.string.settings.feedbackSound()
        case .both:
            return R.string.settings.feedbackBoth()
        }
    }
} 
