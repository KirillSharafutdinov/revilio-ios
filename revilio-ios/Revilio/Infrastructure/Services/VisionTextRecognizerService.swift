//
//  VisionTextRecognizerService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Vision
import CoreMedia
import QuartzCore

/// Manages real-time text recognition using Apple's Vision framework, providing configurable
/// language support, accuracy levels, and thermal throttling. Handles text detection and
/// recognition from camera frames, delivering results through both Combine publishers and
/// async/await interfaces. Includes performance optimization and thermal state management
/// for continuous operation across varying device conditions.
class VisionTextRecognizerService: TextRecognizerRepository {
    // MARK: - Dependencies
    private let logger: Logger
    private let thermalThrottlingService: ThermalThrottlingService
    
    // MARK: - Private Properties
    private var recognitionRequest: VNRecognizeTextRequest?
    private var supportedLanguages: [String] = ["ru-RU", "en-US", "zh-Hans"] //TODO link
    private var minimumTextHeight: Float?
    private var minimumConfidence: Float = 0.5
    /// Persistent sequence handler reused across frames to avoid re-allocation overhead.
    private let sequenceHandler = VNSequenceRequestHandler()
    /// AsyncStream continuations for recognised text consumers.
    private var textContinuations: [AsyncStream<[TextObservation]>.Continuation] = []
    
    // MARK: - Thermal Throttling Properties
    private var lastProcessingTime: TimeInterval = 0
    private var isThrottling: Bool = false
    private var throttleTimer: Timer?
    private let throttleQueue = DispatchQueue(label: "vision-text-thermal-throttle", qos: .userInitiated)
    private var currentProcessingStartTime: TimeInterval = 0
    
    // MARK: - Initialization
    init(logger: Logger = OSLogger(), thermalThrottlingService: ThermalThrottlingService? = nil) {
        self.logger = logger
        self.thermalThrottlingService = thermalThrottlingService ?? ThermalThrottlingService(logger: logger)
        configureTextRecognition(accuracy: .accurate) // Default accuracy for initial setup
    }
    
    deinit {
        stopThrottling()
    }
    
    // MARK: - Public API

    /// Update the list of languages recognised by Vision. This will re-configure the
    /// underlying `VNRecognizeTextRequest` only when the supplied list is different
    /// from the current one, avoiding an expensive teardown/rebuild cycle on every
    /// call that re-passes the same array.
    func setLanguages(_ languages: [String]) {
        guard languages != supportedLanguages else { return }
        
        supportedLanguages = languages
        configureTextRecognition(accuracy: .accurate)

        logger.log(.info,
                   "VisionTextRecognitionService: Updated languages to \(languages)",
                   category: "TEXT_RECOGNITION",
                   file: #file,
                   function: #function,
                   line: #line)
    }
    
    func setMinimumTextHeight(_ height: Float?) {
        minimumTextHeight = height
        logger.log(.debug, "Updated minimum text height to \(minimumTextHeight?.description ?? "nil")", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
    }
    
    func setMinimumConfidence(_ confidence: Float) {
        self.minimumConfidence = confidence
        logger.log(.debug, "Updated minimum confidence to \(self.minimumConfidence)", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
    }
    
    func processFrame(cameraFrame: CameraFrame, accuracy: TextRecognitionAccuracy) {
        if isThrottling {
            logger.log(.debug, 
                       "Dropping frame due to thermal throttling (thermal state: \(thermalThrottlingService.thermalStateDescription(thermalThrottlingService.currentThermalState)))",
                       category: "TEXT_RECOGNITION", 
                       file: #file, 
                       function: #function, 
                       line: #line)
            return
        }
        
        guard let sampleBuffer: CMSampleBuffer = cameraFrame.unwrap() else {
            logger.log(.debug, "Unable to process frame - missing sampleBuffer", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
            return
        }
        
        if recognitionRequest == nil {
            configureTextRecognition(accuracy: accuracy)
        }
        
        guard let request = recognitionRequest else { return }
        
        switch accuracy {
        case .fast:
            request.recognitionLevel = .fast
        case .accurate:
            request.recognitionLevel = .accurate
        }
        
        let orientation = CGImagePropertyOrientation.up
        
        currentProcessingStartTime = CACurrentMediaTime()
        
        do {
            try sequenceHandler.perform([request], on: sampleBuffer, orientation: orientation)
        } catch {
            currentProcessingStartTime = 0
            logger.log(.error, "Error processing text frame - \(error.localizedDescription)", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
            self.textContinuations.forEach { $0.finish() }
        }
    }
    
    // MARK: - Private methods
    
    private func configureTextRecognition(accuracy: TextRecognitionAccuracy) {
        let request: VNRecognizeTextRequest
        if let existing = recognitionRequest {
            request = existing
        } else {
            request = VNRecognizeTextRequest { [weak self] request, error in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    
                    self.handleTextRecognitionResults(request: request, error: error)
                }
            }
            recognitionRequest = request
        }
        
        switch accuracy {
        case .fast:
            request.recognitionLevel = .fast
        case .accurate:
            request.recognitionLevel = .accurate
        }
        
        request.usesLanguageCorrection = true
        
        request.customWords = supportedLanguages
        request.recognitionLanguages = supportedLanguages
        
        if let height = minimumTextHeight {
            request.minimumTextHeight = height
        }
    }
    
    private func handleTextRecognitionResults(request: VNRequest, error: Error?) {
        var processingTime: TimeInterval = 0
        if currentProcessingStartTime > 0 {
            processingTime = (CACurrentMediaTime() - currentProcessingStartTime) * 1000.0
            lastProcessingTime = processingTime
            currentProcessingStartTime = 0
        }
        
        if let error = error {
            logger.log(.error, "Error in text recognition request - \(error.localizedDescription)", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
            textContinuations.forEach { $0.finish() }
            startThermalThrottlingIfNeeded()
            return
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            logger.log(.debug, "No text observations in results", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
            startThermalThrottlingIfNeeded()
            return
        }
        
        if processingTime > 0 {
            logger.log(.info, 
                       String(format: "Text recognition finished in %.1f ms, found %d text observations", processingTime, observations.count),
                       category: "TEXT_RECOGNITION",
                       file: #file,
                       function: #function,
                       line: #line)
        }
        
        let dtoObservations = mapToDTO(observations)
        
        textContinuations.forEach { $0.yield(dtoObservations) }
        
        startThermalThrottlingIfNeeded()
    }
    
    /// Convenience helper to convert Vision observations to domain DTOs.
    private func mapToDTO(_ observations: [VNRecognizedTextObservation]) -> [TextObservation] {
        observations.compactMap { vision in
            guard let topCandidate = vision.topCandidates(1).first else { return nil }
            
            return TextObservation(boundingBox: vision.boundingBox,
                                   text: topCandidate.string,
                                   confidence: vision.confidence)
        }
    }
    
    // MARK: - Thermal Throttling Implementation
    
    private func startThermalThrottlingIfNeeded() {
        let processingTimeToUse = lastProcessingTime > 0 ? lastProcessingTime : 50.0 // 50ms fallback
        
        let throttleDelay = thermalThrottlingService.calculateThrottlingDelay(processingTime: processingTimeToUse, processingType: .textRecognition)
        
        guard throttleDelay > 0 else {
            if isThrottling {
                logger.log(.debug, "Thermal throttling no longer needed for text recognition", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
                stopThrottling()
            }
            return
        }
        
        isThrottling = true
        
        logger.log(.info, 
                   String(format: "Starting thermal throttling for text recognition: %.1f ms delay (thermal state: %@, processing time: %.1f ms)",
                          throttleDelay,
                          thermalThrottlingService.thermalStateDescription(thermalThrottlingService.currentThermalState),
                          processingTimeToUse),
                   category: "TEXT_RECOGNITION",
                   file: #file,
                   function: #function,
                   line: #line)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isThrottling else { return }
            
            self.throttleTimer?.invalidate()
            
            self.throttleTimer = Timer.scheduledTimer(withTimeInterval: throttleDelay / 1000.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                self.logger.log(.debug, 
                               "Thermal throttling timer expired for text recognition",
                               category: "TEXT_RECOGNITION",
                               file: #file,
                               function: #function,
                               line: #line)
                
                self.stopThrottling()
            }
        }
    }
    
    private func stopThrottling() {
        isThrottling = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.throttleTimer?.invalidate()
            self.throttleTimer = nil
            
            self.logger.log(.debug, "Thermal throttling stopped for text recognition", category: "TEXT_RECOGNITION", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - AsyncStream native implementation
    func recognizedTextStream() -> AsyncStream<[TextObservation]> {
        AsyncStream { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.textContinuations.append(continuation)

                continuation.onTermination = { @Sendable _ in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.textContinuations.removeAll { existing in
                            return withUnsafePointer(to: existing) { ptr1 in
                                withUnsafePointer(to: continuation) { ptr2 in
                                    return ptr1 == ptr2
                                }
                            }
                        }
                    }
                }
            }
        }
    }
} 
