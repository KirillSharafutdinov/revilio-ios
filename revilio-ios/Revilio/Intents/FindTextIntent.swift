//
//  FindTextIntent.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//


import AppIntents
import UIKit

/// Manages Siri Shortcuts integration for text search functionality, providing AppIntents
/// entities and queries for voice-initiated text discovery. Handles text query processing
/// and intent execution to launch the main app with specific search parameters.
/// Supports natural language text input and seamless transition to text search mode.
// MARK: - TextQueryEntity
struct TextQueryEntity: AppEntity {
    let id: String
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "findTextTypeDisplayRepresentation"
    static var defaultQuery = TextQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

// MARK: - TextQuery
struct TextQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [TextQueryEntity.ID]) async throws -> [TextQueryEntity] {
        identifiers.map { TextQueryEntity(id: $0) }
    }
    
    func suggestedEntities() async throws -> [TextQueryEntity] {
        []
    }
    
    func entities(matching string: String) async throws -> [TextQueryEntity] {
        [TextQueryEntity(id: string)]
    }
}

// MARK: - FindTextIntent
struct FindTextIntent: AppIntent {
    static var title: LocalizedStringResource = "findTextTitle"
    static var description = IntentDescription("findTextDescription")
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "findTextParameterTitle",
        description: "findTextParameterDescription"
    )
    var query: TextQueryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("findTextSummary") {
            \.$query
        }
    }

    func perform() async throws -> some IntentResult {
        let text = query.id
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .result()
        }
        
        await MainActor.run {
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
            let mainViewModel = appDelegate.dependencyContainer.publicMainViewModel
            mainViewModel.startSearchTextWithKeyboard(text: trimmed.lowercased())
        }
        
        return .result()
    }
}
