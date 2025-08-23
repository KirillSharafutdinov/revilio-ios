//
//  COCOObjectDetectionWrapper.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import CoreML
import UIKit

@objc(COCOObjectDetectionWrapper)
class COCOObjectDetectionWrapper: NSObject {
    
    // MARK: - Static Object Definitions
    
    /// Multi-language object definitions
    /// Format: "class_name_in_model": [language_code: (main_name, [alternative_names])]
    static let objectDefinitions: [String: [String: (main: String, alternatives: [String])]] = [
        "person": [
            "en": ("person", ["people", "man", "woman"]),
            "ru": ("человек", ["люди"]),
            "zh": ("人", ["人们"])
        ],
        "bicycle": [
            "en": ("bicycle", ["bike"]),
            "ru": ("велосипед", []),
            "zh": ("自行车", [])
        ],
        "car": [
            "en": ("car", ["automobile", "vehicle"]),
            "ru": ("машина", ["автомобиль"]),
            "zh": ("汽车", [])
        ],
        "motorbike": [
            "en": ("motorbike", ["motorcycle"]),
            "ru": ("мотоцикл", []),
            "zh": ("摩托车", [])
        ],
        "aeroplane": [
            "en": ("airplane", ["plane"]),
            "ru": ("самолёт", []),
            "zh": ("飞机", [])
        ],
        "bus": [
            "en": ("bus", []),
            "ru": ("автобус", []),
            "zh": ("公共汽车", [])
        ],
        "train": [
            "en": ("train", []),
            "ru": ("поезд", []),
            "zh": ("火车", [])
        ],
        "truck": [
            "en": ("truck", []),
            "ru": ("грузовик", []),
            "zh": ("卡车", [])
        ],
        "boat": [
            "en": ("boat", ["ship"]),
            "ru": ("лодка", []),
            "zh": ("船", [])
        ],
        "traffic light": [
            "en": ("traffic light", []),
            "ru": ("светофор", []),
            "zh": ("红绿灯", [])
        ],
        "fire hydrant": [
            "en": ("fire hydrant", []),
            "ru": ("гидрант", []),
            "zh": ("消防栓", [])
        ],
        "stop sign": [
            "en": ("stop sign", []),
            "ru": ("знак стоп", []),
            "zh": ("停车标志", [])
        ],
        "parking meter": [
            "en": ("parking meter", []),
            "ru": ("парковочный счётчик", []),
            "zh": ("停车计时器", [])
        ],
        "bench": [
            "en": ("bench", []),
            "ru": ("скамейка", ["скамья"]),
            "zh": ("长椅", [])
        ],
        "bird": [
            "en": ("bird", []),
            "ru": ("птица", []),
            "zh": ("鸟", [])
        ],
        "cat": [
            "en": ("cat", ["kitten"]),
            "ru": ("кошка", ["кот", "киса"]),
            "zh": ("猫", [])
        ],
        "dog": [
            "en": ("dog", ["puppy"]),
            "ru": ("собака", ["пёс"]),
            "zh": ("狗", [])
        ],
        "horse": [
            "en": ("horse", []),
            "ru": ("лошадь", []),
            "zh": ("马", [])
        ],
        "sheep": [
            "en": ("sheep", []),
            "ru": ("овца", []),
            "zh": ("羊", [])
        ],
        "cow": [
            "en": ("cow", []),
            "ru": ("корова", []),
            "zh": ("牛", [])
        ],
        "elephant": [
            "en": ("elephant", []),
            "ru": ("слон", []),
            "zh": ("大象", [])
        ],
        "bear": [
            "en": ("bear", []),
            "ru": ("медведь", []),
            "zh": ("熊", [])
        ],
        "zebra": [
            "en": ("zebra", []),
            "ru": ("зебра", []),
            "zh": ("斑马", [])
        ],
        "giraffe": [
            "en": ("giraffe", []),
            "ru": ("жираф", []),
            "zh": ("长颈鹿", [])
        ],
        "backpack": [
            "en": ("backpack", ["bag"]),
            "ru": ("рюкзак", []),
            "zh": ("背包", [])
        ],
        "umbrella": [
            "en": ("umbrella", []),
            "ru": ("зонт", ["зонтик"]),
            "zh": ("雨伞", [])
        ],
        "handbag": [
            "en": ("handbag", ["purse"]),
            "ru": ("сумка", ["сумочка"]),
            "zh": ("手提包", [])
        ],
        "tie": [
            "en": ("tie", ["necktie"]),
            "ru": ("галстук", []),
            "zh": ("领带", [])
        ],
        "suitcase": [
            "en": ("suitcase", ["luggage"]),
            "ru": ("чемодан", ["кейс"]),
            "zh": ("行李箱", [])
        ],
        "frisbee": [
            "en": ("frisbee", []),
            "ru": ("фризби", []),
            "zh": ("飞盘", [])
        ],
        "skis": [
            "en": ("skis", ["ski"]),
            "ru": ("лыжи", ["лыжа"]),
            "zh": ("滑雪板", [])
        ],
        "snowboard": [
            "en": ("snowboard", []),
            "ru": ("сноуборд", []),
            "zh": ("滑雪板", [])
        ],
        "sports ball": [
            "en": ("ball", ["sports ball"]),
            "ru": ("мяч", ["мячик"]),
            "zh": ("球", [])
        ],
        "kite": [
            "en": ("kite", []),
            "ru": ("воздушный змей", []),
            "zh": ("风筝", [])
        ],
        "baseball bat": [
            "en": ("baseball bat", ["bat"]),
            "ru": ("бита", ["убита", "убито"]),
            "zh": ("棒球棒", [])
        ],
        "baseball glove": [
            "en": ("baseball glove", ["glove"]),
            "ru": ("бейсбольная перчатка", []),
            "zh": ("棒球手套", [])
        ],
        "skateboard": [
            "en": ("skateboard", []),
            "ru": ("скейтборд", []),
            "zh": ("滑板", [])
        ],
        "surfboard": [
            "en": ("surfboard", []),
            "ru": ("доска для сёрфинга", []),
            "zh": ("冲浪板", [])
        ],
        "tennis racket": [
            "en": ("tennis racket", ["racket"]),
            "ru": ("теннисная ракетка", []),
            "zh": ("网球拍", [])
        ],
        "bottle": [
            "en": ("bottle", []),
            "ru": ("бутылка", ["бутыль"]),
            "zh": ("瓶子", [])
        ],
        "wine glass": [
            "en": ("wine glass", ["glass"]),
            "ru": ("бокал", ["фужер"]),
            "zh": ("酒杯", [])
        ],
        "cup": [
            "en": ("cup", ["mug"]),
            "ru": ("кружка", ["крошка", "чашка"]),
            "zh": ("杯子", [])
        ],
        "fork": [
            "en": ("fork", []),
            "ru": ("вилка", []),
            "zh": ("叉子", [])
        ],
        "knife": [
            "en": ("knife", []),
            "ru": ("нож", ["наш"]),
            "zh": ("刀", [])
        ],
        "spoon": [
            "en": ("spoon", []),
            "ru": ("ложка", []),
            "zh": ("勺子", [])
        ],
        "bowl": [
            "en": ("bowl", []),
            "ru": ("чаша", []),
            "zh": ("碗", [])
        ],
        "banana": [
            "en": ("banana", []),
            "ru": ("банан", []),
            "zh": ("香蕉", [])
        ],
        "apple": [
            "en": ("apple", []),
            "ru": ("яблоко", []),
            "zh": ("苹果", [])
        ],
        "sandwich": [
            "en": ("sandwich", []),
            "ru": ("сэндвич", []),
            "zh": ("三明治", [])
        ],
        "orange": [
            "en": ("orange", []),
            "ru": ("апельсин", ["мандарин"]),
            "zh": ("橙子", [])
        ],
        "broccoli": [
            "en": ("broccoli", []),
            "ru": ("брокколи", []),
            "zh": ("西兰花", [])
        ],
        "carrot": [
            "en": ("carrot", []),
            "ru": ("морковь", ["морковка"]),
            "zh": ("胡萝卜", [])
        ],
        "hot dog": [
            "en": ("hot dog", []),
            "ru": ("хот дог", []),
            "zh": ("热狗", [])
        ],
        "pizza": [
            "en": ("pizza", []),
            "ru": ("пицца", []),
            "zh": ("披萨", [])
        ],
        "donut": [
            "en": ("donut", ["doughnut"]),
            "ru": ("пончик", ["бублик"]),
            "zh": ("甜甜圈", [])
        ],
        "cake": [
            "en": ("cake", []),
            "ru": ("торт", ["пирог"]),
            "zh": ("蛋糕", [])
        ],
        "chair": [
            "en": ("chair", []),
            "ru": ("кресло", []),
            "zh": ("椅子", [])
        ],
        "sofa": [
            "en": ("sofa", ["couch"]),
            "ru": ("диван", []),
            "zh": ("沙发", [])
        ],
        "pottedplant": [
            "en": ("potted plant", ["plant"]),
            "ru": ("растение в горшке", ["растения в горшке"]),
            "zh": ("盆栽", [])
        ],
        "bed": [
            "en": ("bed", []),
            "ru": ("кровать", []),
            "zh": ("床", [])
        ],
        "dining table": [
            "en": ("dining table", ["table"]),
            "ru": ("стол", []),
            "zh": ("餐桌", [])
        ],
        "toilet": [
            "en": ("toilet", []),
            "ru": ("унитаз", ["туалет"]),
            "zh": ("马桶", [])
        ],
        "tv": [
            "en": ("TV", ["television"]),
            "ru": ("телевизор", ["монитор"]),
            "zh": ("电视", [])
        ],
        "laptop": [
            "en": ("laptop", ["computer"]),
            "ru": ("ноутбук", ["ноут"]),
            "zh": ("笔记本电脑", [])
        ],
        "mouse": [
            "en": ("mouse", []),
            "ru": ("мышь", []),
            "zh": ("鼠标", [])
        ],
        "remote": [
            "en": ("remote", ["remote control"]),
            "ru": ("пульт", []),
            "zh": ("遥控器", [])
        ],
        "keyboard": [
            "en": ("keyboard", []),
            "ru": ("клавиатура", ["клава"]),
            "zh": ("键盘", [])
        ],
        "cell phone": [
            "en": ("cell phone", ["phone", "mobile"]),
            "ru": ("телефон", ["сотовый"]),
            "zh": ("手机", [])
        ],
        "microwave": [
            "en": ("microwave", []),
            "ru": ("микроволновая печь", ["микроволновка", "микроволновая"]),
            "zh": ("微波炉", [])
        ],
        "oven": [
            "en": ("oven", []),
            "ru": ("печь", ["духовка"]),
            "zh": ("烤箱", [])
        ],
        "toaster": [
            "en": ("toaster", []),
            "ru": ("тостер", []),
            "zh": ("烤面包机", [])
        ],
        "sink": [
            "en": ("sink", []),
            "ru": ("раковина", ["умывальник"]),
            "zh": ("水槽", [])
        ],
        "refrigerator": [
            "en": ("refrigerator", ["fridge"]),
            "ru": ("холодильник", []),
            "zh": ("冰箱", [])
        ],
        "book": [
            "en": ("book", []),
            "ru": ("книга", []),
            "zh": ("书", [])
        ],
        "clock": [
            "en": ("clock", ["watch"]),
            "ru": ("часы", []),
            "zh": ("时钟", [])
        ],
        "vase": [
            "en": ("vase", []),
            "ru": ("ваза", []),
            "zh": ("花瓶", [])
        ],
        "scissors": [
            "en": ("scissors", []),
            "ru": ("ножницы", []),
            "zh": ("剪刀", [])
        ],
        "teddy bear": [
            "en": ("teddy bear", ["bear"]),
            "ru": ("плюшевый мишка", []),
            "zh": ("泰迪熊", [])
        ],
        "hair drier": [
            "en": ("hair dryer", ["dryer"]),
            "ru": ("фен", []),
            "zh": ("吹风机", [])
        ],
        "toothbrush": [
            "en": ("toothbrush", []),
            "ru": ("зубная щетка", []),
            "zh": ("牙刷", [])
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
    static let modelName = "yolo11mCOCO"
    
    /// Model Prediction Input Type
    @objc(COCOObjectDetectionWrapperInput)
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
    @objc(COCOObjectDetectionWrapperOutput)
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
        let modelURL = COCOObjectDetectionWrapper.modelURL(for: configuration)
        let model = try MLModel(contentsOf: modelURL)
        self.init(model: model)
    }
    
    /// Default initializer with default configuration
    @objc
    convenience override init() {
        // We have to force try here since we're overriding a non-throwing initializer
        // However, we'll provide a detailed error message if this fails
        do {
            try self.init(configuration: COCOObjectDetectionWrapper.defaultModelConfiguration)
        } catch {
            fatalError("Failed to initialize COCOObjectDetectionWrapper with default configuration: \(error)")
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
            throw NSError(domain: "COCOObjectDetectionWrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to get detections output"])
        }
        
        return Output(detections: detections)
    }
    
    /// Private helper to get the model URL
    private class func modelURL(for configuration: MLModelConfiguration) -> URL {
        // Get the base URL for the app bundle
        guard let bundleURL = Bundle.main.url(forResource: "yolo11mCOCO", withExtension: "mlmodelc") else {
            fatalError("Missing the yolo11mCOCO.mlmodelc resource in the bundle")
        }
        
        return bundleURL
    }
}
