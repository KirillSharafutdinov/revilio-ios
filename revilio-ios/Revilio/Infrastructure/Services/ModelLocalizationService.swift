//
//  ModelLocalizationService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Service responsible for providing localized names for ML models and their sections
class ModelLocalizationService {
    
    // MARK: - Singleton
    
    static let shared = ModelLocalizationService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get localized section names for models
    /// - Returns: Dictionary mapping model names to their localized display names
    func getLocalizedModelNames() -> [String: String] {
        let currentLanguage = getCurrentLanguageCode()
        
        let modelNames: [String: [String: String]] = [
            COCOObjectDetectionWrapper.modelName: [
                "en": "COCO Objects",
                "ru": "Объекты COCO",
                "zh": "COCO 对象"
            ],
            Custom15ObjectDetectionWrapper.modelName: [
                "en": "Custom Objects",
                "ru": "Пользовательские объекты",
                "zh": "自定义对象"
            ]
        ]
        
        var result: [String: String] = [:]
        for (modelName, translations) in modelNames {
            if let localizedName = translations[currentLanguage] {
                result[modelName] = localizedName
            } else if let englishName = translations["en"] {
                result[modelName] = englishName
            } else {
                result[modelName] = modelName
            }
        }
        
        return result
    }
    
    /// Get localized name for a specific model
    /// - Parameter modelName: Internal model name
    /// - Returns: Localized display name
    func getLocalizedModelName(for modelName: String) -> String {
        let localizedNames = getLocalizedModelNames()
        return localizedNames[modelName] ?? modelName
    }
    
    /// Get object definitions for COCO model in current language
    /// - Returns: Dictionary with class names mapped to localized names
    func getCOCOObjectDefinitions() -> [String: (main: String, alternatives: [String])] {
        let currentLanguage = getCurrentLanguageCode()
        return COCOObjectDetectionWrapper.getObjectDefinitions(for: currentLanguage)
    }
    
    /// Get object definitions for Custom15 model in current language
    /// - Returns: Dictionary with class names mapped to localized names
    func getCustom15ObjectDefinitions() -> [String: (main: String, alternatives: [String])] {
        let currentLanguage = getCurrentLanguageCode()
        return Custom15ObjectDetectionWrapper.getObjectDefinitions(for: currentLanguage)
    }
    
    /// Get object definitions for any model in current language
    /// - Parameter modelName: Name of the model
    /// - Returns: Dictionary with class names mapped to localized names
    func getObjectDefinitions(for modelName: String) -> [String: (main: String, alternatives: [String])] {
        let currentLanguage = getCurrentLanguageCode()
        
        switch modelName {
        case COCOObjectDetectionWrapper.modelName:
            return COCOObjectDetectionWrapper.getObjectDefinitions(for: currentLanguage)
        case Custom15ObjectDetectionWrapper.modelName:
            return Custom15ObjectDetectionWrapper.getObjectDefinitions(for: currentLanguage)
        default:
            return [:]
        }
    }
    
    // MARK: - Private Methods
    
    /// Get current language code from LocalizationManager
    /// - Returns: Language code (en, ru, zh) with fallback to "en"
    func getCurrentLanguageCode() -> String {
        let currentLanguage = LocalizationManager.shared.currentLanguage
        
        // Map AppLanguage to our supported codes
        switch currentLanguage {
        case .en:
            return "en"
        case .ru:
            return "ru"
        case .zhHans:
            return "zh"
        }
    }
} 
