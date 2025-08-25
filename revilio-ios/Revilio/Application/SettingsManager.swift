//
//  SettingsManager.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Centralised runtime-accessible settings model (user preferences).
/// Additional toggles can be added here to avoid scattered UserDefaults look-ups
/// and NotificationCenter traffic. Mimics the pattern used by LocalizationManager.
final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Published state
    /// Indicates whether the Training button on the main screen is enabled.
    @Published private(set) var trainingMenuEnabled: Bool
    var trainingMenuEnabledPublisher: AnyPublisher<Bool, Never> {
        $trainingMenuEnabled.eraseToAnyPublisher()
    }

    // MARK: - Storage
    private let trainingMenuKey = "settings.trainingMenuEnabled"

    private init() {
        // Read persisted value; default to false (disabled).
        let stored = UserDefaults.standard.integer(forKey: trainingMenuKey)
        trainingMenuEnabled = (stored == 1)
    }

    // MARK: - Public API
    func setTrainingMenuEnabled(_ enabled: Bool) {
        guard enabled != trainingMenuEnabled else { return }
        trainingMenuEnabled = enabled
        UserDefaults.standard.set(enabled ? 1 : 0, forKey: trainingMenuKey)
    }
} 
