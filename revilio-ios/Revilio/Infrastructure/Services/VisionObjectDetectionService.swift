//
//  VisionObjectDetectionService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Vision
import CoreML
import CoreMedia
import CoreGraphics
import QuartzCore

/// Manages real-time object detection using Apple's Vision framework with Core ML integration,
/// providing configurable confidence thresholds and thermal throttling. Handles model loading,
/// frame processing, and delivers detection results through both Combine publishers and async/await
/// interfaces. Includes performance optimization and thermal state management for continuous operation.
class VisionObjectDetectionService: ObjectDetectionRepository {
    // MARK: - Dependencies
    private let logger: Logger
    private let thermalThrottlingService: ThermalThrottlingService
    
    // MARK: - Private Properties
    // Static cache shared by all instances to avoid re-loading the same Core ML
    // model multiple times during the lifetime of the app.  The first call to
    // `initialize(modelName:)` incurs the loading cost; subsequent requests for
    // the *same* model return instantly.
    private static var modelCache: [String: MLModel] = [:]
    
    private var mlModel: MLModel?
    private var visionModel: VNCoreMLModel?
    private var visionRequest: VNCoreMLRequest?
    private var confidenceThreshold: Double = 0.25
    private var iouThreshold: Double = 0.45
    /// Keeps track of the last successfully initialised model so that we can
    /// early-exit when the caller requests the same model again.
    private var currentModelName: String?
    /// AsyncStream continuations for structured-concurrency consumers.
    private var detectionContinuations: [AsyncStream<[ObjectObservation]>.Continuation] = []
    
    // MARK: - Thermal Throttling Properties
    private var lastProcessingTime: TimeInterval = 0
    private var isThrottling: Bool = false
    private var throttleTimer: Timer?
    private let throttleQueue = DispatchQueue(label: "vision-thermal-throttle", qos: .userInitiated)
    private var currentProcessingStartTime: TimeInterval = 0
    
    // MARK: - Initialization
    init(logger: Logger = OSLogger(), thermalThrottlingService: ThermalThrottlingService? = nil) {
        self.logger = logger
        self.thermalThrottlingService = thermalThrottlingService ?? ThermalThrottlingService(logger: logger)
    }
    
    deinit {
        stopThrottling()
    }
    
    // MARK: - Public API
    
    func initialize(modelName: String) {
        // Fast-path: if the requested model is already active we simply return.
        if currentModelName == modelName && mlModel != nil && visionRequest != nil {
            logger.log(.info, "VisionObjectDetectionService: Reusing previously initialised model '\(modelName)'", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            return
        }

        // Attempt to fetch the model from the in-memory cache first.
        if let cached = Self.modelCache[modelName] {
            self.mlModel = cached
            configureVisionModel()
            currentModelName = modelName
            logger.log(.info, "VisionObjectDetectionService: Initialised from cache '\(modelName)'", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            return
        }

        do {
            if modelName == "yolo11mCOCO" {
                // Load the model using our custom wrapper class with optimized configuration
                let config = MLModelConfiguration()
                // Use Neural Engine when available, fallback to CPU+GPU
                config.computeUnits = .cpuAndNeuralEngine
                // Optimize for memory efficiency to reduce MPSGraphExecutable cache issues
                config.allowLowPrecisionAccumulationOnGPU = true
                
                // Try to load using our custom wrapper
                let modelWrapper = try COCOObjectDetectionWrapper(configuration: config)
                self.mlModel = modelWrapper.model
            } else if modelName == "yolov8mCustom15" {
                // Load the model using our custom wrapper class with optimized configuration
                let config = MLModelConfiguration()
                // Use Neural Engine when available, fallback to CPU+GPU
                config.computeUnits = .cpuAndNeuralEngine
                // Optimize for memory efficiency to reduce MPSGraphExecutable cache issues
                config.allowLowPrecisionAccumulationOnGPU = true
                
                // Try to load using our custom wrapper
                let modelWrapper = try Custom15ObjectDetectionWrapper(configuration: config)
                self.mlModel = modelWrapper.model
            } else {
                throw NSError(domain: "VisionObjectDetectionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported model name: \(modelName)"])
            }
            
            configureVisionModel()
            
            if let readyModel = self.mlModel {
                Self.modelCache[modelName] = readyModel
            }
            
            currentModelName = modelName
        
            logger.log(.info, "VisionObjectDetectionService: Successfully initialized model '\(modelName)' with Neural Engine", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
        } catch {
            logger.log(.error, "VisionObjectDetectionService: Error initializing model - \(error.localizedDescription)", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            for cont in detectionContinuations {
                cont.finish()
            }
        }
    }
    
    func processFrame(cameraFrame: CameraFrame) {
        if isThrottling {
            logger.log(.debug, 
                       "Dropping frame due to thermal throttling (thermal state: \(thermalThrottlingService.thermalStateDescription(thermalThrottlingService.currentThermalState)))",
                       category: "OBJECT_DETECTION",
                       file: #file, 
                       function: #function, 
                       line: #line)
            return
        }
        
        guard let sampleBuffer: CMSampleBuffer = cameraFrame.unwrap(),
              let visionRequest = visionRequest else {
            logger.log(.debug, "Unable to process frame - missing sampleBuffer or visionRequest", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            return
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        
        currentProcessingStartTime = CACurrentMediaTime()
        
        do {
            try handler.perform([visionRequest])
        } catch {
            logger.log(.error, "Error processing frame - \(error.localizedDescription)", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            currentProcessingStartTime = 0 // Reset on error
        }
    }
    
    func setConfidenceThreshold(_ threshold: Double) {
        self.confidenceThreshold = threshold
        configureDetectionParameters()
    }
    
    func setIoUThreshold(_ threshold: Double) {
        self.iouThreshold = threshold
        configureDetectionParameters()
    }
    
    // MARK: - AsyncStream native implementation
    func detectionsStream() -> AsyncStream<[ObjectObservation]> {
        AsyncStream { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.detectionContinuations.append(continuation)

                continuation.onTermination = { @Sendable _ in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.detectionContinuations.removeAll { existing in
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
    
    // MARK: - Private methods
    
    private func configureDetectionParameters() {
        guard mlModel != nil else {
            logger.log(.warn, "No ML model available for configuration", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            return
        }
        
        let mlModelConfiguration = MLModelConfiguration()
        mlModelConfiguration.computeUnits = .cpuAndNeuralEngine
        
        logger.log(.debug, "Configured ML model with iouThreshold=\(iouThreshold), confidenceThreshold=\(confidenceThreshold)", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
    }
    
    private func handleDetectionResults(request: VNRequest, error: Error?) {
        var processingTime: TimeInterval = 0
        if currentProcessingStartTime > 0 {
            processingTime = (CACurrentMediaTime() - currentProcessingStartTime) * 1000.0
            lastProcessingTime = processingTime
            currentProcessingStartTime = 0 // Reset for next frame
        }
        
        if let error = error {
            logger.log(.error, "Error in ML request - \(error.localizedDescription)", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            startThermalThrottlingIfNeeded()
            return
        }
        
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            logger.log(.debug, "No object observations in results", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            startThermalThrottlingIfNeeded()
            return
        }
        
        if processingTime > 0 {
            logger.log(.info, 
                       String(format: "Object detection finished in %.1f ms", processingTime),
                       category: "OBJECT_DETECTION",
                       file: #file,
                       function: #function,
                       line: #line)
        }
        
        let dtoDetections = mapToDTO(results)
        
        for cont in detectionContinuations {
            cont.yield(dtoDetections)
        }
        
        startThermalThrottlingIfNeeded()
        
        if !results.isEmpty {
            let labels = results.compactMap { $0.labels.first?.identifier }.joined(separator: ", ")
            logger.log(.debug, "Detected objects: \(labels)", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
        }
    }
    
    private func configureVisionModel() {
        guard let model = mlModel else { return }
        
        do {
            let visionModel = try VNCoreMLModel(for: model)
            self.visionRequest = VNCoreMLRequest(model: visionModel, completionHandler: handleDetectionResults)
            logger.log(.info, "Vision model and request configured successfully", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
        } catch {
            logger.log(.error, "Error configuring vision model - \(error.localizedDescription)", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Thermal Throttling Implementation
    
    private func startThermalThrottlingIfNeeded() {
        let processingTimeToUse = lastProcessingTime > 0 ? lastProcessingTime : 50.0 // 50ms fallback
        
        let throttleDelay = thermalThrottlingService.calculateThrottlingDelay(processingTime: processingTimeToUse, processingType: .objectDetection)
        
        guard throttleDelay > 0 else {
            if isThrottling {
                logger.log(.debug, "Thermal throttling no longer needed", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
                stopThrottling()
            }
            return
        }
        
        guard !isThrottling else {
            logger.log(.debug, "Thermal throttling already active, skipping", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
            return
        }
        
        // Start throttling
        isThrottling = true
        
        logger.log(.info, 
                   String(format: "Starting thermal throttling: %.1f ms delay (thermal state: %@, processing time: %.1f ms)",
                          throttleDelay,
                          thermalThrottlingService.thermalStateDescription(thermalThrottlingService.currentThermalState),
                          processingTimeToUse),
                   category: "OBJECT_DETECTION",
                   file: #file,
                   function: #function,
                   line: #line)
        
        throttleTimer?.invalidate()
        
        DispatchQueue.main.async { [weak self] in
            self?.throttleTimer = Timer.scheduledTimer(withTimeInterval: throttleDelay / 1000.0, repeats: false) { [weak self] _ in
                self?.stopThrottling()
            }
        }
    }
    
    private func stopThrottling() {
        isThrottling = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.throttleTimer?.invalidate()
            self.throttleTimer = nil
            
            self.logger.log(.debug, "Thermal throttling stopped", category: "OBJECT_DETECTION", file: #file, function: #function, line: #line)
        }
    }
    
    // Convenience helper to convert Vision observations to domain DTOs.
    private func mapToDTO(_ observations: [VNRecognizedObjectObservation]) -> [ObjectObservation] {
        observations.map { vision in
            let label = vision.labels.first?.identifier ?? "Unknown"
            return ObjectObservation(label: label,
                                     boundingBox: vision.boundingBox,
                                     confidence: vision.confidence)
        }
    }
}

// MARK: - Threshold Provider

/// Provides custom IoU and confidence thresholds for adjusting model predictions.
class ThresholdProvider: MLFeatureProvider {
    /// Stores IoU and confidence thresholds as MLFeatureValue objects.
    private var values: [String: MLFeatureValue]
    
    /// The set of feature names provided by this provider.
    var featureNames: Set<String> {
        return Set(values.keys)
    }
    
    /// Initializes the provider with specified IoU and confidence thresholds.
    /// - Parameters:
    ///   - iouThreshold: The IoU threshold for determining object overlap.
    ///   - confidenceThreshold: The minimum confidence for considering a detection valid.
    init(iouThreshold: Double = 0.45, confidenceThreshold: Double = 0.25) {
        values = [
            "iouThreshold": MLFeatureValue(double: iouThreshold),
            "confidenceThreshold": MLFeatureValue(double: confidenceThreshold)
        ]
    }
    
    /// Returns the feature value for the given feature name.
    /// - Parameter featureName: The name of the feature.
    /// - Returns: The MLFeatureValue object corresponding to the feature name.
    func featureValue(for featureName: String) -> MLFeatureValue? {
        return values[featureName]
    }
} 
