//
//  BoundingBox.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics

/// Represents a bounding box for detected objects or text.
struct BoundingBox {
    var rect: CGRect
    var label: String
    var confidence: Float
    
    init(rect: CGRect, label: String = "", confidence: Float = 0.0) {
        self.rect = rect
        self.label = label
        self.confidence = confidence
    }
    
    /// Calculates the center point of the bounding box.
    var center: CGPoint {
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    
    /// Calculates the distance to a specific point.
    func distance(to point: CGPoint) -> CGFloat {
        return hypot(center.x - point.x, center.y - point.y)
    }
    
    /// Checks if this bounding box contains a specific point.
    func contains(point: CGPoint) -> Bool {
        return rect.contains(point)
    }
} 
