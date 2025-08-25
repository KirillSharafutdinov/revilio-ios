//
//  BaseSearchUseCase.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics
import Combine

/// Base class that provides shared helpers (logging, prediction parameters) and hosts a `SearchSession`.
/// Concrete use-cases should access mutable detection state through the forwarded properties.  This decouples
/// session-lifetime data from the use-case object and will soon allow us to extract the session into its own
/// orchestrator component.
class BaseSearchUseCase {
    // MARK: – Prediction engine
    let prediction: PredictionService

    // MARK: – Logging
    private let logger: Logger
    /// Optional closure that higher layers (UI) can use to receive plain-text log entries.
    var onLogMessage: ((String) -> Void)?

    // MARK: – Init
    init(predictionParameters: PredictionParameters = .default,
         logger: Logger = OSLogger()) {
        self.logger = logger
        self.prediction = PredictionService(parameters: predictionParameters)
    }

    // MARK: – Logging helper
    func log(_ message: String,
             level: LogLevel = .debug,
             category: String = "",
             file: String = #file,
             function: String = #function,
             line: Int = #line) {
        logger.log(level, message, category: category, file: file, function: function, line: line)
        onLogMessage?(message)
    }
}
