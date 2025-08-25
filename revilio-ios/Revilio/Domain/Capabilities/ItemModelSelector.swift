//
//  ItemModelSelector.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Resolves which ML model should be used for a requested human-readable item name.
public protocol ItemModelSelecting {
    /// Returns the name of the Core ML model that contains the given item. Returns `nil` when unknown.
    func modelName(for displayName: String) -> String?
    /// Returns localisation-aware display name (e.g. Russian) for the item, falling back to original.
    func originalDisplayName(for displayName: String) -> String
    /// Returns the internal model class name corresponding to the requested display name.
    func className(for displayName: String) -> String?
    /// Attempts to find an item using **partial** matching when exact lookup fails.
    /// - Parameter displayName: Localised name spoken/selected by the user.
    /// - Returns: Tuple of `(modelName, classNameInModel, originalName)` when a fuzzy match was found, otherwise `nil`.
    func partialMatch(for displayName: String) -> (modelName: String, classNameInModel: String, originalName: String)?
}

/// Default implementation backed by the shared `ItemsForSearchRegistryService`.
public final class DefaultItemModelSelector: ItemModelSelecting {
    private let registry = ItemsForSearchRegistryService.shared

    public init() {}

    public func modelName(for displayName: String) -> String? {
        registry.searchObject(byRussianName: displayName.lowercased())?.modelName
    }

    public func originalDisplayName(for displayName: String) -> String {
        registry.searchObject(byRussianName: displayName.lowercased())?.mainLocalizedName ?? displayName
    }

    public func className(for displayName: String) -> String? {
        registry.searchObject(byRussianName: displayName.lowercased())?.classNameInModel
    }

    public func partialMatch(for displayName: String) -> (modelName: String, classNameInModel: String, originalName: String)? {
        guard let result = registry.searchObjectWithPartialMatching(byRussianName: displayName.lowercased()) else {
            return nil
        }
        return (modelName: result.modelName,
                classNameInModel: result.classNameInModel,
                originalName: result.mainLocalizedName)
    }
} 
