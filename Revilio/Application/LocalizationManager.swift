//
//  LocalizationManager.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine
import UIKit
import ObjectiveC.runtime

/// Supported application languages.
/// Keeps the mapping to ISO locale identifiers used by AVSpeechSynthesizer and formatters.
enum AppLanguage: String, CaseIterable {
    case ru = "ru"
    case en = "en"
    case zhHans = "zh-Hans"
    
    /// System locale identifier that best matches the app language.
    var localeId: String {
        switch self {
        case .ru:     return "ru-RU"
        case .en:     return "en-US"
        case .zhHans: return "zh-CN"
        }
    }
}

/// Central point for run-time language switching.
/// Stores the user's choice in `UserDefaults`, falls back to the first system language or Russian.
final class LocalizationManager {
    // MARK: - Shared Instance

    static let shared = LocalizationManager()

    // MARK: - Published Properties
    
    @Published private(set) var currentLanguage: AppLanguage
    
    // MARK: - Public Publishers
    /// Reactive publisher for language changes. Replaces NotificationCenter.languageChanged.
    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        $currentLanguage.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    private let storageKey = "AppLanguagePreference"
    private var cancellables = Set<AnyCancellable>()
    /// Tracks whether we have already installed the Bundle localization swizzle. We
    /// must only exchange the method implementations once – calling the swizzle a
    /// second time would effectively revert to the original behaviour.
    private var didInstallSwizzle = false

    // MARK: - Initialization
    private init() {
        
        // Determine initial language.
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let saved = AppLanguage(rawValue: raw) {
            currentLanguage = saved
        } else {
            let systemLangCode = Locale.preferredLanguages.first ?? "ru"
            // Pick the first supported language that matches the system language prefix.
            currentLanguage = AppLanguage.allCases.first(where: { systemLangCode.hasPrefix($0.rawValue) }) ?? .ru
        }

        activateBundle(for: currentLanguage)
    }

    // MARK: - Public API

    /// Switch the whole application to another language at run-time.
    func set(language: AppLanguage) {
        
        guard language != currentLanguage else { 
            return 
        }
        
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)

        activateBundle(for: language)
        
        
        // Update speech synthesiser – safe to ignore if the service isn't available yet.
        do {
            let speechSynthesizer = try resolveSpeechSynthesizer()
            speechSynthesizer.setVoice(for: language.localeId)
        } catch {
        }
        
        // Update speech recognizer
        do {
            let speechRecognizer = try resolveSpeechRecognizer()
            speechRecognizer.setLanguage(for: language.localeId)
        } catch {
        }

        forceUIRefresh()

        SearchableItemsCache.shared.updateCacheIfNeeded()
        RevilioShortcuts.updateAppShortcutParameters()
    }
    
    // MARK: - Language Resolution

    private func resolveSpeechSynthesizer() throws -> SpeechSynthesizerRepository {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            return appDelegate.dependencyContainer.speechSynthesizer
        }
        throw NSError(domain: "LocalizationManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not resolve speech synthesizer"])
    }
    
    private func resolveSpeechRecognizer() throws -> SpeechRecognizerRepository { // TODO
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            return appDelegate.dependencyContainer.speechRecognizer
        }
        throw NSError(domain: "LocalizationManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not resolve speech recognizer"])
    }
    
    // MARK: - Bundle Management
    
    private func activateBundle(for language: AppLanguage) {
        let lprojName = language.rawValue
        
        // Prefer the dedicated "Resources/Localization" directory which actually contains the .strings files (modern layout).
        let preferredPath = Bundle.main.path(forResource: lprojName,
                                             ofType: "lproj",
                                             inDirectory: "Resources/Localization")

        // Fallback to a root-level *.lproj directory (used on real device).
        let legacyPath = Bundle.main.path(forResource: lprojName, ofType: "lproj")

        let resolvedPath = preferredPath ?? legacyPath

        guard let path = resolvedPath else {
            return
        }
        
        guard let langBundle = Bundle(path: path) else {
            return
        }
        
        // Install the method swizzle only on the first call to avoid toggling
        // the implementations back to the originals. Subsequent invocations only
        // update the associated bundle reference so that look-ups resolve to the
        // newly selected language.
        if !didInstallSwizzle {
            Bundle.swizzleLocalization(with: langBundle)
            didInstallSwizzle = true
        } else {
            Bundle.associateLanguageBundle(langBundle)
        }
    }
    
    // MARK: - UI Refresh
    /// Forces comprehensive UI refresh for all visible view controllers without recreating them
    /// This approach maintains app state while ensuring localization changes are applied
    private func forceUIRefresh() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return
            }
            self.refreshViewControllerHierarchy(window.rootViewController)
            window.setNeedsLayout(); window.layoutIfNeeded()
            self.refreshNavigationBars(window.rootViewController)
            self.refreshPresentedContent(window.rootViewController)
        }
    }

    /// Recursively refreshes all view controllers in the hierarchy.
    private func refreshViewControllerHierarchy(_ viewController: UIViewController?) {
        guard let vc = viewController else { return }
        vc.loadViewIfNeeded(); vc.view.setNeedsLayout(); vc.view.layoutIfNeeded();
        vc.viewWillAppear(false)
        vc.children.forEach { refreshViewControllerHierarchy($0) }
        if let presented = vc.presentedViewController { refreshViewControllerHierarchy(presented) }
        if let tab = vc as? UITabBarController { tab.viewControllers?.forEach { refreshViewControllerHierarchy($0) } }
        if let nav = vc as? UINavigationController { nav.viewControllers.forEach { refreshViewControllerHierarchy($0) } }
    }

    private func refreshNavigationBars(_ viewController: UIViewController?) {
        guard let vc = viewController else { return }
        vc.navigationController?.navigationBar.setNeedsLayout(); vc.navigationController?.navigationBar.layoutIfNeeded()
        vc.children.forEach { refreshNavigationBars($0) }
        if let presented = vc.presentedViewController { refreshNavigationBars(presented) }
    }

    private func refreshPresentedContent(_ viewController: UIViewController?) {
        guard let vc = viewController else { return }
        if let presented = vc.presentedViewController { refreshPresentedContent(presented) }
        vc.children.forEach { refreshPresentedContent($0) }
    }
}

// MARK: - Bundle swizzling

private extension Bundle {

    static func swizzleLocalization(with bundle: Bundle) {
        associateLanguageBundle(bundle)
        
        guard self === Bundle.self else { return }
        let originalSelector = #selector(localizedString(forKey:value:table:))
        let swizzledSelector = #selector(swizzled_localizedString(forKey:value:table:))

        guard let originalMethod = class_getInstanceMethod(self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(self, swizzledSelector) else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    /// Stores / replaces the current language bundle on both the *class* and the
    /// main instance so that **all** bundles use the same lookup table.
    static func associateLanguageBundle(_ bundle: Bundle) {
        objc_setAssociatedObject(Bundle.self, &AssociatedKeys.languageBundle, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(Bundle.main, &AssociatedKeys.languageBundle, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @objc func swizzled_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // Look up the language bundle **stored on the class** (global for all instances).
        if let bundle = objc_getAssociatedObject(Bundle.self, &AssociatedKeys.languageBundle) as? Bundle {
            return bundle.swizzled_localizedString(forKey: key, value: value, table: tableName)
        }
        // Fallback – no custom bundle set yet.
        return swizzled_localizedString(forKey: key, value: value, table: tableName)
    }
    
    private struct AssociatedKeys {
        static var languageBundle: UInt8 = 0
    }
}
