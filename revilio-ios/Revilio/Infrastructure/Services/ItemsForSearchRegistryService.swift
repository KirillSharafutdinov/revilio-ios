//
//  ItemsForSearchRegistryService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Result of an object search containing the matched object info
struct ItemSearchResult {
    let modelName: String
    let classNameInModel: String
    let mainLocalizedName: String
    let matchedLocalizedName: String
}

/// Information about an item that can be displayed in the search list
public struct ItemDisplayInfo {
    /// The name of the ML model this item belongs to
    let modelName: String
    /// The class name as defined in the ML model (always in English)
    let classNameInModel: String
    /// The localized main name for display (e.g., Russian for Russian language)
    let displayName: String
    /// Alternative localized names for this item (if any)
    let alternativeNames: [String]
    
    /// Creates a new ItemDisplayInfo instance
    init(modelName: String, classNameInModel: String, displayName: String, alternativeNames: [String] = []) {
        self.modelName = modelName
        self.classNameInModel = classNameInModel
        self.displayName = displayName
        self.alternativeNames = alternativeNames
    }
}

/// A group of items from the same ML model for organized display
public struct ModelGroup {
    /// The name of the ML model
    let modelName: String
    /// Localized display name for the model section (e.g., "COCO Objects")
    let displayName: String
    /// List of items in this model group
    let items: [ItemDisplayInfo]
    
    /// Creates a new ModelGroup instance
    init(modelName: String, displayName: String, items: [ItemDisplayInfo]) {
        self.modelName = modelName
        self.displayName = displayName
        self.items = items
    }
}


/// Service for centralized object search across all ML models
class ItemsForSearchRegistryService {
    
    /// Singleton instance
    static let shared = ItemsForSearchRegistryService()
    
    private init() {}
    
    // MARK: - Public API

    /// Search for an object by localized name across all available models
    /// - Parameter russianName: The localized name spoken by the user (parameter name kept for backward compatibility)
    /// - Returns: ObjectSearchResult if found, nil otherwise
    func searchObject(byRussianName russianName: String) -> ItemSearchResult? {
        let searchText = russianName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Search in COCO model first (more common objects)
        if let result = searchInModel(
            searchText: searchText,
            modelName: COCOObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCOCOObjectDefinitions()
        ) {
            return result
        }
        
        // Search in Custom15 model
        if let result = searchInModel(
            searchText: searchText,
            modelName: Custom15ObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCustom15ObjectDefinitions()
        ) {
            return result
        }
        
        return nil
    }
    
    /// Search for objects using partial matching (for when exact match fails)
    /// - Parameter russianName: The localized name spoken by the user (parameter name kept for backward compatibility)
    /// - Returns: ObjectSearchResult if found, nil otherwise
    func searchObjectWithPartialMatching(byRussianName russianName: String) -> ItemSearchResult? {
        let searchText = russianName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only try partial matching if the search text is long enough
        guard searchText.count >= 3 else { return nil }
        
        var bestMatch: ItemSearchResult?
        var bestMatchScore = 0
        
        // Search with partial matching in COCO model
        if let result = searchInModelWithPartialMatching(
            searchText: searchText,
            modelName: COCOObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCOCOObjectDefinitions()
        ) {
            let score = result.matchedLocalizedName.count
            if score > bestMatchScore {
                bestMatchScore = score
                bestMatch = result
            }
        }
        
        // Search with partial matching in Custom15 model
        if let result = searchInModelWithPartialMatching(
            searchText: searchText,
            modelName: Custom15ObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCustom15ObjectDefinitions()
        ) {
            let score = result.matchedLocalizedName.count
            if score > bestMatchScore {
                bestMatchScore = score
                bestMatch = result
            }
        }
        
        // Only return if we found a meaningful match (at least 3 characters)
        return bestMatchScore >= 3 ? bestMatch : nil
    }
    
    /// Get all available object class names for a specific model (for UI purposes)
    /// - Parameter modelName: Name of the model
    /// - Returns: Array of class names in the model
    func getAllClassNames(forModel modelName: String) -> [String] {
        switch modelName {
        case COCOObjectDetectionWrapper.modelName:
            return Array(ModelLocalizationService.shared.getCOCOObjectDefinitions().keys)
        case Custom15ObjectDetectionWrapper.modelName:
            return Array(ModelLocalizationService.shared.getCustom15ObjectDefinitions().keys)
        default:
            return []
        }
    }
    
    //TODO ???
    /// Get all available object class names across all models (for UI purposes)
    /// - Returns: Array of all class names
    func getAllAvailableClassNames() -> [String] {
        var allClassNames: [String] = []
        allClassNames.append(contentsOf: getAllClassNames(forModel: COCOObjectDetectionWrapper.modelName))
        allClassNames.append(contentsOf: getAllClassNames(forModel: Custom15ObjectDetectionWrapper.modelName))
        return allClassNames
    }
    
    /// Get all available items formatted for display in the list interface
    /// - Returns: Array of ItemDisplayInfo objects with localized names
    func getAllAvailableItemsForDisplay() -> [ItemDisplayInfo] {
        var displayItems: [ItemDisplayInfo] = []
        
        // Process COCO model items
        let cocoItems = getItemsForDisplay(
            modelName: COCOObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCOCOObjectDefinitions()
        )
        displayItems.append(contentsOf: cocoItems)
        
        // Process Custom15 model items
        let custom15Items = getItemsForDisplay(
            modelName: Custom15ObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCustom15ObjectDefinitions()
        )
        displayItems.append(contentsOf: custom15Items)
        
        return displayItems
    }
    
    /// Get items grouped by model for organized display
    /// - Returns: Array of ModelGroup objects
    func getItemsGroupedByModel() -> [ModelGroup] {
        var modelGroups: [ModelGroup] = []
        
        // COCO model group
        let cocoItems = getItemsForDisplay(
            modelName: COCOObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCOCOObjectDefinitions()
        )
        if !cocoItems.isEmpty {
            let cocoGroup = ModelGroup(
                modelName: COCOObjectDetectionWrapper.modelName,
                displayName: ModelLocalizationService.shared.getLocalizedModelName(for: COCOObjectDetectionWrapper.modelName),
                items: cocoItems.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            )
            modelGroups.append(cocoGroup)
        }
        
        // Custom15 model group
        let custom15Items = getItemsForDisplay(
            modelName: Custom15ObjectDetectionWrapper.modelName,
            objectDefinitions: ModelLocalizationService.shared.getCustom15ObjectDefinitions()
        )
        if !custom15Items.isEmpty {
            let custom15Group = ModelGroup(
                modelName: Custom15ObjectDetectionWrapper.modelName,
                displayName: ModelLocalizationService.shared.getLocalizedModelName(for: Custom15ObjectDetectionWrapper.modelName),
                items: custom15Items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            )
            modelGroups.append(custom15Group)
        }
        
        return modelGroups
    }
    
    /// Gets the localized base class name given the class name in the model.
    /// /// - Parameters:
    /// /// - classNameInModel: The name of the class in the model (e.g. "car")
    /// /// - languageCode: The language code (e.g. "ru", "en", "zh"). If not specified, the current device language is taken.
    /// /// - Returns: The localized base name if the class is found, otherwise nil
    func localizedName(forClassName classNameInModel: String) -> String {
        // Определяем код языка
        let langCode: String = ModelLocalizationService.shared.getCurrentLanguageCode()

        if let mainName = COCOObjectDetectionWrapper.getObjectDefinitions(for: langCode)[classNameInModel]?.main {
            return mainName
        }

        if let mainName = Custom15ObjectDetectionWrapper.getObjectDefinitions(for: langCode)[classNameInModel]?.main {
            return mainName
        }
        
        return ""
    }
    
    // MARK: - Private Methods
    
    /// Convert object definitions to ItemDisplayInfo for a specific model
    /// - Parameters:
    ///   - modelName: Name of the ML model
    ///   - objectDefinitions: Dictionary of object definitions from the model wrapper
    /// - Returns: Array of ItemDisplayInfo objects
    private func getItemsForDisplay(
        modelName: String,
        objectDefinitions: [String: (main: String, alternatives: [String])]
    ) -> [ItemDisplayInfo] {
        return objectDefinitions.map { (classNameInModel, definition) in
            ItemDisplayInfo(
                modelName: modelName,
                classNameInModel: classNameInModel,
                displayName: definition.main,
                alternativeNames: definition.alternatives
            )
        }
    }
    
    /// Get localized display name for a model
    /// - Parameter modelName: Internal model name
    /// - Returns: Localized display name
    private func getLocalizedModelName(_ modelName: String) -> String {
        return ModelLocalizationService.shared.getLocalizedModelName(for: modelName)
    }
    
    private func searchInModel(
        searchText: String,
        modelName: String,
        objectDefinitions: [String: (main: String, alternatives: [String])]
    ) -> ItemSearchResult? {
        
        for (classNameInModel, definition) in objectDefinitions {
            // Check main name
            if definition.main.lowercased() == searchText {
                return ItemSearchResult(
                    modelName: modelName,
                    classNameInModel: classNameInModel,
                    mainLocalizedName: definition.main,
                    matchedLocalizedName: definition.main
                )
            }
            
            // Check alternative names
            for alternative in definition.alternatives {
                if alternative.lowercased() == searchText {
                    return ItemSearchResult(
                        modelName: modelName,
                        classNameInModel: classNameInModel,
                        mainLocalizedName: definition.main,
                        matchedLocalizedName: alternative
                    )
                }
            }
        }
        
        return nil
    }
    
    private func searchInModelWithPartialMatching(
        searchText: String,
        modelName: String,
        objectDefinitions: [String: (main: String, alternatives: [String])]
    ) -> ItemSearchResult? {
        
        var bestMatch: ItemSearchResult?
        var bestMatchScore = 0
        
        for (classNameInModel, definition) in objectDefinitions {
            // Check main name with partial matching
            if let score = calculatePartialMatchScore(searchText: searchText, targetText: definition.main.lowercased()) {
                if score > bestMatchScore {
                    bestMatchScore = score
                    bestMatch = ItemSearchResult(
                        modelName: modelName,
                        classNameInModel: classNameInModel,
                        mainLocalizedName: definition.main,
                        matchedLocalizedName: definition.main
                    )
                }
            }
            
            // Check alternative names with partial matching
            for alternative in definition.alternatives {
                if let score = calculatePartialMatchScore(searchText: searchText, targetText: alternative.lowercased()) {
                    if score > bestMatchScore {
                        bestMatchScore = score
                        bestMatch = ItemSearchResult(
                            modelName: modelName,
                            classNameInModel: classNameInModel,
                            mainLocalizedName: definition.main,
                            matchedLocalizedName: alternative
                        )
                    }
                }
            }
        }
        
        return bestMatchScore >= 3 ? bestMatch : nil
    }
    
    private func calculatePartialMatchScore(searchText: String, targetText: String) -> Int? {
        // Check if searchText is contained in targetText or vice versa
        if targetText.contains(searchText) {
            return searchText.count
        } else if searchText.contains(targetText) {
            return targetText.count
        }
        
        // Check for word-based partial matching
        let searchWords = searchText.components(separatedBy: " ")
        let targetWords = targetText.components(separatedBy: " ")
        
        for searchWord in searchWords {
            guard searchWord.count >= 3 else { continue }
            for targetWord in targetWords {
                if targetWord.count >= 3 && (
                    targetWord.contains(searchWord) || searchWord.contains(targetWord)
                ) {
                    return min(searchWord.count, targetWord.count)
                }
            }
        }
        
        return nil
    }
}

extension ItemsForSearchRegistryService {
    func itemForEntity(modelName: String, classNameInModel: String) -> ItemDisplayInfo? {
        let allItems = getAllAvailableItemsForDisplay()
        return allItems.first { $0.modelName == modelName && $0.classNameInModel == classNameInModel }
    }
}
