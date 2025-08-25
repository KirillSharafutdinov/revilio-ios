//
//  AppDelegate.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    // Dependency container
    let dependencyContainer = DependencyContainer()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register global default preferences early so that business logic
        // sees the correct initial values even before the Settings screen
        UserDefaults.standard.register(defaults: SettingsViewController.defaultUserDefaults)

        // Apply global button tint and font appearance
        UIButton.appearance().setTitleColor(.white, for: .normal)
        UIButton.appearance().setTitleColor(.white, for: .highlighted)

        // Trigger UIViewController swizzling to automatically apply accessibility styling
        _ = UIViewController.enableAccessibilityStylingAutomaticSwizzle
        
        initializeSearchItemsCache()
        
        RevilioShortcuts.updateAppShortcutParameters()

        // SceneDelegate handles the window setup on iOS 13+. No additional work required here.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

extension AppDelegate {
    func initializeSearchItemsCache() {
        SearchableItemsCache.shared.updateCacheIfNeeded()
    }
}
