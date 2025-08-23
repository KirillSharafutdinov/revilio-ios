//
//  FallbackFrameQualityService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Fallback implementation of FrameQualityRepository when Metal is unavailable
/// This provides a basic implementation that always returns nil for frame quality
/// to prevent crashes while maintaining the interface contract
class FallbackFrameQualityService: FrameQualityRepository {
    private let logger: Logger
    
    init(logger: Logger) {
        self.logger = logger
        logger.log(.info, "FallbackFrameQualityService initialized - Metal unavailable", category: "FRAME_QUALITY", file: #file, function: #function, line: #line)
    }
    
    func evaluate(frame: CameraFrame) async -> FrameSharpnessData? {
        // Return nil to indicate no quality data available
        // This allows the app to continue functioning without frame quality evaluation
        return nil
    }
} 
