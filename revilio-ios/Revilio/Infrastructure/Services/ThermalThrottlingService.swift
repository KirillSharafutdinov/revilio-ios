//
//  ThermalThrottlingService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Types of processing operations that can be throttled
public enum ProcessingType {
    case objectDetection
    case textRecognition
}

/// Service that monitors device thermal state and provides throttling recommendations
/// for computationally intensive operations like object detection and text recognition.
final class ThermalThrottlingService {
    
    // MARK: - Public API
    
    /// Current thermal state of the device
    var currentThermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
    
    /// Publisher that emits when thermal state changes
    var thermalStatePublisher: AnyPublisher<ProcessInfo.ThermalState, Never> {
        thermalStateSubject.eraseToAnyPublisher()
    }
    
    /// Calculate throttling delay based on processing time and current thermal state
    /// - Parameters:
    ///   - processingTime: Time taken to process the last frame in milliseconds
    ///   - processingType: Type of processing (object detection or text recognition)
    /// - Returns: Delay in milliseconds (capped at different limits for different processing types)
    func calculateThrottlingDelay(processingTime: TimeInterval, processingType: ProcessingType) -> TimeInterval {
        let thermalState = currentThermalState
        let delayPercentage = thermalDelayPercentage(for: thermalState)
        let calculatedDelay = processingTime * delayPercentage
        
        let maxDelay = maxDelayForProcessingType(processingType)
        let finalDelay = min(calculatedDelay, maxDelay)
        
        return finalDelay
    }
    
    // MARK: - Private Properties
    
    private let thermalStateSubject = PassthroughSubject<ProcessInfo.ThermalState, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let logger: Logger
    
    // MARK: - Initialization
    
    init(logger: Logger = OSLogger()) {
        self.logger = logger
        setupThermalStateMonitoring()
        
        // Log initial thermal state
        logger.log(.info, 
                   "ThermalThrottlingService initialized with thermal state: \(thermalStateDescription(currentThermalState))",
                   category: "THERMAL_THROTTLING",
                   file: #file,
                   function: #function,
                   line: #line)
    }
    
    // MARK: - Private Methods
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let newState = self.currentThermalState
                
                self.logger.log(.info,
                               "Thermal state changed to: \(self.thermalStateDescription(newState))",
                               category: "THERMAL_THROTTLING",
                               file: #file,
                               function: #function,
                               line: #line)
                
                self.thermalStateSubject.send(newState)
            }
            .store(in: &cancellables)
    }
    
    private func thermalDelayPercentage(for state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal:
            return 0.0  // 0% delay
        case .fair:
            return 0.3 // 30% delay
        case .serious:
            return 0.7  // 70% delay
        case .critical:
            return 1.5  // 150% delay
        @unknown default:
            return 0.0  // Default to no throttling for unknown states
        }
    }
    
    private func maxDelayForProcessingType(_ processingType: ProcessingType) -> TimeInterval {
        switch processingType {
        case .objectDetection:
            return Constants.ThermalThrottling.maxDelayObjectDetectionMs
        case .textRecognition:
            return Constants.ThermalThrottling.maxDelayTextRecognitionMs
        }
    }
    
    func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - Constants Extension

extension Constants {
    enum ThermalThrottling {
        /// Maximum throttling delay for object detection in milliseconds
        static let maxDelayObjectDetectionMs: TimeInterval = 150.0
        /// Maximum throttling delay for text recognition in milliseconds
        static let maxDelayTextRecognitionMs: TimeInterval = 500.0
    }
} 
