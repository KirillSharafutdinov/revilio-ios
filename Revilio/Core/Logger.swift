//
//  Logger.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import os

/// Log levels to categorise importance and filter output
public enum LogLevel: String {
    case debug
    case info
    case warn
    case error
}

/// Protocol describing a logging façade that can be injected anywhere in the code-base.
public protocol Logger {
    /// Logs a message.
    ///
    /// - Parameters:
    ///   - level: Level of the log entry (debug / info / warn / error)
    ///   - message: The message string to be logged.
    ///   - category: Optional category to further filter logs (e.g. "SEARCH_TEXT").
    ///   - file: File name from which the call was made.
    ///   - function: Function name from which the call was made.
    ///   - line: Line number of the call site.
    func log(_ level: LogLevel,
             _ message: String,
             category: String,
             file: String,
             function: String,
             line: Int)
}

// MARK: - os.Logger based implementation

/// Default implementation that writes to Unified Logging subsystem via os.Logger.
public struct OSLogger: Logger {

    private let logger: os.Logger

    /// Creates a new logger instance.
    /// - Parameters:
    ///   - subsystem: The logging subsystem. Defaults to the main bundle identifier.
    ///   - category: The default category used by this logger instance.
    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "App",
                category: String = "General") {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    public func log(_ level: LogLevel,
                    _ message: String,
                    category: String = "",
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        let levelPrefix = "[\(level.rawValue.uppercased())]"
        let categoryPrefix = category.isEmpty ? "" : "[\(category)] "
        let context = "\(levelPrefix) \(categoryPrefix)\((file as NSString).lastPathComponent):\(line) \(function) - \(message)"

        switch level {
        case .debug:
            logger.debug("\(context)")
        case .info:
            logger.info("\(context)")
        case .warn:
            logger.log(level: .default, "\(context)")
        case .error:
            logger.error("\(context)")
        }

        // Broadcast via EventBus for interested observers (e.g. on-device log overlay).
        EventBus.shared.send(.log(level, context))
    }
} 
