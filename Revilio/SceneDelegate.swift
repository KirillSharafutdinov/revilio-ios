//
//  SceneDelegate.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // Get dependency container from AppDelegate
    private var dependencyContainer: DependencyContainer {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            fatalError("AppDelegate not found")
        }
        return appDelegate.dependencyContainer
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Create window with the correct frame
        window = UIWindow(windowScene: windowScene)
        
        // Onboarding check
        if UserDefaults.standard.bool(forKey: AppStorageKeys.hasCompletedOnboarding) {
            showMainInterface()
        } else {
            showOnboardingFlow()
        }
        
        window?.makeKeyAndVisible()
    }
    
    // MARK: - Flow Management
        
    private func showOnboardingFlow() {
        let languageVC = LanguageSelectionViewController()
        let navController = UINavigationController(rootViewController: languageVC)
        window?.rootViewController = navController
    }
        
    private func showMainInterface() {
        let mainViewController = dependencyContainer.makeMainViewController()
        window?.rootViewController = mainViewController
    }
        
        // MARK: - Transition after onboarding
        
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.hasCompletedOnboarding)
        showMainInterface()
        
        UIView.transition(with: window!,
                          duration: 0.5,
                          options: .transitionCrossDissolve,
                          animations: nil,
                          completion: nil)
    }
}

