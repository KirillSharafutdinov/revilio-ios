//
//  FindItemIntent.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

/// Manages Siri Shortcuts integration for object search functionality, providing AppIntents
/// entities and queries for seamless voice-controlled item discovery. Handles item caching,
/// search suggestions, and intent execution to launch the main app with specific search parameters.
/// Supports multi-language item names and alternative naming for robust voice recognition.
import AppIntents
import UIKit

// MARK: - SearchableItemEntity
struct SearchableItemEntity: AppEntity, Codable {
    let id: String
    let modelName: String
    let classNameInModel: String
    let displayName: String
    let alternativeNames: [String]

    init(id: String, modelName: String, classNameInModel: String, displayName: String, alternativeNames: [String]) {
        self.id = id
        self.modelName = modelName
        self.classNameInModel = classNameInModel
        self.displayName = displayName
        self.alternativeNames = alternativeNames
    }

    init(item: ItemDisplayInfo) {
        self.id = "\(item.modelName)|\(item.classNameInModel)"
        self.modelName = item.modelName
        self.classNameInModel = item.classNameInModel
        self.displayName = item.displayName
        self.alternativeNames = item.alternativeNames
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "findItemTypeDisplayRepresentation"
    static var defaultQuery = SearchableItemQuery()
}

// MARK: - SearchableItemQuery
struct SearchableItemQuery: EntityQuery, EntityStringQuery {
    private var cachedEntities: [SearchableItemEntity] {
        SearchableItemsCache.shared.loadCachedEntities()
    }
    
    func entities(for identifiers: [SearchableItemEntity.ID]) async throws -> [SearchableItemEntity] {
        return cachedEntities.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [SearchableItemEntity] {
        return cachedEntities
    }
    
    func entities(matching string: String) async throws -> [SearchableItemEntity] {
        let searchText = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedEntities.filter { entity in
            if entity.displayName.lowercased().contains(searchText) {
                return true
            }
            return entity.alternativeNames.contains { $0.lowercased().contains(searchText) }
        }
    }
}

// MARK: - Items Cache
final class SearchableItemsCache {
    static let shared = SearchableItemsCache()
    private let cacheKey = "SearchableItemsCacheKey"
    
    func cacheEntities(_ entities: [SearchableItemEntity]) {
        do {
            let data = try JSONEncoder().encode(entities)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            print("Failed to cache searchable items: \(error)")
        }
    }
    
    func loadCachedEntities() -> [SearchableItemEntity] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        do {
            return try JSONDecoder().decode([SearchableItemEntity].self, from: data)
        } catch {
            print("Failed to load cached searchable items: \(error)")
            return []
        }
    }
    
    func updateCacheIfNeeded() {
        let currentItems = ItemsForSearchRegistryService.shared.getAllAvailableItemsForDisplay()
        let currentEntities = currentItems.map(SearchableItemEntity.init)
        cacheEntities(currentEntities)
    }
}

// MARK: - FindItemIntent
struct FindItemIntent: AppIntent {
    static var title: LocalizedStringResource = "findItemTitle"
    static var description = IntentDescription("findItemDescription")
    
    static var openAppWhenRun: Bool { true }
    
    @Parameter(
        title: "findItemParameterTitle",
        description: "findItemParameterDescription"
    )
    var item: SearchableItemEntity
    
    static var parameterSummary: some ParameterSummary {
        Summary("findItemSummary") {
            \.$item
        }
    }
    
    func perform() async throws -> some IntentResult {
        if let freshItem = ItemsForSearchRegistryService.shared.itemForEntity(
            modelName: item.modelName,
            classNameInModel: item.classNameInModel
        ) {
            await startSearch(
                modelName: item.modelName,
                classNameInModel: item.classNameInModel,
                displayName: freshItem.displayName
            )
            return .result()
        }
        else if let searchResult = ItemsForSearchRegistryService.shared.searchObject(byRussianName: item.displayName) {
            await startSearch(
                modelName: searchResult.modelName,
                classNameInModel: searchResult.classNameInModel,
                displayName: searchResult.mainLocalizedName
            )
            return .result()
        }
        else {
            return .result()
        }
    }
    
    private func startSearch(
        modelName: String,
        classNameInModel: String,
        displayName: String
    ) async {
        await MainActor.run {
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
            let mainViewModel = appDelegate.dependencyContainer.publicMainViewModel
            mainViewModel.startSearchItemFromList(
                itemName: displayName,
                modelName: modelName
            )
        }
    }
}
