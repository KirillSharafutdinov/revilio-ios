//
//  TextObservation.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics

/// Pure Swift representation of a piece of recognised text.
struct TextObservation: Identifiable, Equatable {
    let id: UUID
    let boundingBox: CGRect
    let text: String
    let confidence: Float

    init(id: UUID = UUID(),
         boundingBox: CGRect,
         text: String,
         confidence: Float) {
        self.id = id
        self.boundingBox = boundingBox
        self.text = text
        self.confidence = confidence
    }
} 
