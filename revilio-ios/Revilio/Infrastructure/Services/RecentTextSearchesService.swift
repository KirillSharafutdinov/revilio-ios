//
//  RecentTextSearchesService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Service for managing recent text search history with persistent storage
/// Stores up to 10 recent search terms in UserDefaults, maintaining chronological order
final class RecentTextSearchesService {
    
    // MARK: - Singleton
    static let shared = RecentTextSearchesService()
    
    // MARK: - Constants
    private let storageKey = "recent.textSearches"
    private let maxRecentSearches = 10
    
    // MARK: - Thread Safety
    private let queue = DispatchQueue(label: "recentTextSearches.queue", qos: .utility)
    
    // MARK: - Initialization
    private init() {
        // Private initializer to enforce singleton pattern
    }
    
    // MARK: - Public Methods
    
    /// Add a new search term to the recent searches
    /// - Parameter text: The search term to add
    /// - Note: Automatically removes duplicates and maintains max count
    func addRecentSearch(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Validate input
        guard !trimmedText.isEmpty else {
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var recentSearches = self.loadRecentSearches()
            
            // Remove existing occurrence if present (to avoid duplicates)
            if let existingIndex = recentSearches.firstIndex(of: trimmedText) {
                recentSearches.remove(at: existingIndex)
            }
            
            // Add to the beginning (most recent)
            recentSearches.insert(trimmedText, at: 0)
            
            // Limit to maximum count
            if recentSearches.count > self.maxRecentSearches {
                recentSearches = Array(recentSearches.prefix(self.maxRecentSearches))
            }
            
            // Save to UserDefaults
            UserDefaults.standard.set(recentSearches, forKey: self.storageKey)
            
        }
    }
    
    /// Get all recent searches in chronological order (most recent first)
    /// - Returns: Array of recent search terms
    func getRecentSearches() -> [String] {
        return queue.sync {
            return loadRecentSearches()
        }
    }
    
    /// Remove a specific search term from recent searches
    /// - Parameter text: The search term to remove
    func removeRecentSearch(_ text: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var recentSearches = self.loadRecentSearches()
            
            if let index = recentSearches.firstIndex(of: text) {
                recentSearches.remove(at: index)
                UserDefaults.standard.set(recentSearches, forKey: self.storageKey)
            }
        }
    }
    
    /// Clear all recent searches
    func clearRecentSearches() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            UserDefaults.standard.removeObject(forKey: self.storageKey)
        }
    }
    
    /// Get count of recent searches (for UI purposes)
    /// - Returns: Number of stored recent searches
    func getRecentSearchesCount() -> Int {
        return queue.sync {
            return loadRecentSearches().count
        }
    }
    
    // MARK: - Private Methods
    
    /// Load recent searches from UserDefaults
    /// - Returns: Array of recent search terms
    private func loadRecentSearches() -> [String] {
        guard let searches = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
            return []
        }
        
        // Filter out any empty or whitespace-only entries that might have been stored
        return searches.compactMap { search in
            let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
} 
