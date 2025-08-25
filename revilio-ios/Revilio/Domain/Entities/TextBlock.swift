//
//  TextBlock.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import CoreGraphics

/// Lightweight wrapper around a recognised text fragment used by the Read-Text flow.
/// Keeps a reference to the pure-Swift `TextObservation` while also exposing a
/// convenient `BoundingBox` value object for UI/high-level geometric operations.
struct TextBlock {
    var text: String
    var boundingBox: BoundingBox
    var observation: TextObservation

    init(text: String, boundingBox: BoundingBox, observation: TextObservation) {
        self.text = text
        self.boundingBox = boundingBox
        self.observation = observation
    }

    /// Factory helper converting a `TextObservation` DTO into a rich `TextBlock`.
    static func from(observation: TextObservation) -> TextBlock {
        let boundingBox = BoundingBox(
            rect: observation.boundingBox,
            label: observation.text,
            confidence: observation.confidence
        )

        return TextBlock(text: observation.text, boundingBox: boundingBox, observation: observation)
    }
} 
