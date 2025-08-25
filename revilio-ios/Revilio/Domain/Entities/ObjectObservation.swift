//
//  ObjectObservation.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Pure Swift DTO representing an object detected on screen or in camera input.
struct ObjectObservation: Identifiable, Equatable {
    let id: UUID
    let label: String
    let boundingBox: CGRect
    let confidence: Float

    init(id: UUID = UUID(),
         label: String,
         boundingBox: CGRect,
         confidence: Float) {
        self.id = id
        self.label = label
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}
