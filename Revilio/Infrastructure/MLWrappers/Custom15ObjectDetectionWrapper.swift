//
//  Custom15ObjectDetectionWrapper.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import CoreML
import UIKit

@objc(Custom15ObjectDetectionWrapper)
class Custom15ObjectDetectionWrapper: NSObject {
    
    // MARK: - Static Object Definitions
    
    /// Multi-language object definitions
    /// Format: "class_name_in_model": [language_code: (main_name, [alternative_names])]
    static let objectDefinitions: [String: [String: (main: String, alternatives: [String])]] = [
        "Glasses": [
            "en": ("glasses", ["eyeglasses", "spectacles"]),
            "ru": ("очки", []),
            "zh": ("眼镜", [])
        ],
        "Knitted hat": [
            "en": ("knitted hat", ["beanie", "winter hat"]),
            "ru": ("шапка", []),
            "zh": ("针织帽", [])
        ],
        "Hat": [
            "en": ("hat", []),
            "ru": ("шляпа", []),
            "zh": ("帽子", [])
        ],
        "White cane": [
            "en": ("white cane", ["cane"]),
            "ru": ("белая трость", []),
            "zh": ("白色手杖", [])
        ],
        "Cap": [
            "en": ("cap", ["baseball cap"]),
            "ru": ("кепка", ["бейсболка"]),
            "zh": ("帽子", [])
        ],
        "Door handle": [
            "en": ("door handle", ["handle"]),
            "ru": ("дверная ручка", ["верная ручка"]),
            "zh": ("门把手", [])
        ],
        "Glove": [
            "en": ("glove", ["gloves"]),
            "ru": ("перчатка", ["перчатки"]),
            "zh": ("手套", [])
        ],
        "Hand dryer": [
            "en": ("hand dryer", ["dryer"]),
            "ru": ("сушилка для рук", ["сушилка"]),
            "zh": ("干手器", [])
        ],
        "Light switch": [
            "en": ("light switch", ["switch"]),
            "ru": ("выключатель", []),
            "zh": ("电灯开关", [])
        ],
        "Keys": [
            "en": ("keys", ["key"]),
            "ru": ("ключи", ["ключ", "включи"]),
            "zh": ("钥匙", [])
        ],
        "Power plugs and sockets": [
            "en": ("power outlet", ["outlet", "socket", "plug"]),
            "ru": ("розетка", ["электричество"]),
            "zh": ("电源插座", [])
        ],
        "Screwdriver": [
            "en": ("screwdriver", []),
            "ru": ("отвёртка", []),
            "zh": ("螺丝刀", [])
        ],
        "Tap": [
            "en": ("tap", ["faucet"]),
            "ru": ("кран", ["помыть руки"]),
            "zh": ("水龙头", [])
        ],
        "Wallet": [
            "en": ("wallet", ["purse"]),
            "ru": ("кошелек", ["бумажник"]),
            "zh": ("钱包", [])
        ],
        "Toilet paper": [
            "en": ("toilet paper", ["tissue"]),
            "ru": ("туалетная бумага", []),
            "zh": ("卫生纸", [])
        ]
    ]
    
    /// Get object definitions for a specific language
    /// - Parameter languageCode: Language code (en, ru, zh)
    /// - Returns: Dictionary with class names mapped to localized names
    static func getObjectDefinitions(for languageCode: String) -> [String: (main: String, alternatives: [String])] {
        var result: [String: (main: String, alternatives: [String])] = [:]
        
        for (className, languageDict) in objectDefinitions {
            if let localizedDef = languageDict[languageCode] {
                result[className] = localizedDef
            } else if let englishDef = languageDict["en"] {
                // Fallback to English if the requested language is not available
                result[className] = englishDef
            }
        }
        
        return result
    }
    
    /// Get the model name identifier
    static let modelName = "yolov8mCustom15"
    
    /// Model Prediction Input Type
    @objc(Custom15ObjectDetectionWrapperInput)
    class Input: NSObject {
        
        /// Input image to be analyzed (bgr format)
        var image: CVPixelBuffer
        
        /// Confidence threshold for filtering predicted bounding boxes
        var confidenceThreshold: Double?
        
        /// IoU threshold for non-maximum suppression
        var iouThreshold: Double?
        
        @objc
        init(image: CVPixelBuffer) {
            self.image = image
            self.confidenceThreshold = nil
            self.iouThreshold = nil
        }
        
        init(image: CVPixelBuffer, confidenceThreshold: Double?, iouThreshold: Double?) {
            self.image = image
            self.confidenceThreshold = confidenceThreshold
            self.iouThreshold = iouThreshold
        }
    }
    
    /// Model Prediction Output Type
    @objc(Custom15ObjectDetectionWrapperOutput)
    class Output: NSObject {
        
        /// Array of detected objects in the image
        @objc var detections: MLMultiArray
        
        @objc
        init(detections: MLMultiArray) {
            self.detections = detections
        }
    }
    
    /// The Core ML model wrapped by this class
    let model: MLModel
    private static let defaultModelConfiguration = MLModelConfiguration()
    
    /// Initialize with the model URL
    @objc
    init(model: MLModel) {
        self.model = model
        super.init()
    }
    
    /// Initialize with a configuration
    @objc
    convenience init(configuration: MLModelConfiguration) throws {
        let modelURL = Custom15ObjectDetectionWrapper.modelURL(for: configuration)
        let model = try MLModel(contentsOf: modelURL)
        self.init(model: model)
    }
    
    /// Default initializer with default configuration
    @objc
    convenience override init() {
        // We have to force try here since we're overriding a non-throwing initializer
        // However, we'll provide a detailed error message if this fails
        do {
            try self.init(configuration: Custom15ObjectDetectionWrapper.defaultModelConfiguration)
        } catch {
            fatalError("Failed to initialize Custom15ObjectDetectionWrapper with default configuration: \(error)")
        }
    }
    
    /// Make a prediction with the model (Objective-C compatible method)
    @objc
    func prediction(image: CVPixelBuffer) throws -> Output {
        let input = Input(image: image)
        return try prediction(input: input)
    }
    
    /// Make a prediction with confidence and IoU thresholds (Swift-only method)
    func prediction(image: CVPixelBuffer, confidenceThreshold: Double?, iouThreshold: Double?) throws -> Output {
        let input = Input(image: image, confidenceThreshold: confidenceThreshold, iouThreshold: iouThreshold)
        return try prediction(input: input)
    }
    
    /// Make a prediction with an Input object
    @objc
    func prediction(input: Input) throws -> Output {
        var featureDict = [String: MLFeatureValue]()
        
        featureDict["image"] = MLFeatureValue(pixelBuffer: input.image)
        
        if let confidenceThreshold = input.confidenceThreshold {
            featureDict["confidenceThreshold"] = MLFeatureValue(double: confidenceThreshold)
        }
        
        if let iouThreshold = input.iouThreshold {
            featureDict["iouThreshold"] = MLFeatureValue(double: iouThreshold)
        }
        
        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: featureDict)
        
        let outFeatures = try model.prediction(from: inputFeatures)
        
        guard let detections = outFeatures.featureValue(for: "detections")?.multiArrayValue else {
            throw NSError(domain: "Custom15ObjectDetectionWrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to get detections output"])
        }
        
        return Output(detections: detections)
    }
    
    /// Private helper to get the model URL
    private class func modelURL(for configuration: MLModelConfiguration) -> URL {
        // Get the base URL for the app bundle
        guard let bundleURL = Bundle.main.url(forResource: "yolov8mCustom15", withExtension: "mlmodelc") else {
            fatalError("Missing the yolov8mCustom15.mlmodelc resource in the bundle")
        }
        
        return bundleURL
    }
}
