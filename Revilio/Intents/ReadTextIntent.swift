//
//  ReadTextIntent.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import AppIntents
import UIKit

/// Manages Siri Shortcuts integration for text-to-speech functionality, providing AppIntent
/// for voice-initiated text reading. Handles intent execution to launch the main app
/// and activate text reading mode through seamless voice command integration.
struct ReadTextIntent: AppIntent {
    static var title: LocalizedStringResource = "readTextTitle"
    static var description = IntentDescription("readTextDescription")
    static var openAppWhenRun: Bool { true }
    
    static var parameterSummary: some ParameterSummary {
        Summary("readTextSummary")
    }
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
            let mainViewModel = appDelegate.dependencyContainer.publicMainViewModel
            mainViewModel.startReadText()
        }
        return .result()
    }
}
