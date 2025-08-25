//
//  BoundingQuad.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import CoreGraphics

/// Represents a convex quadrilateral in Vision normalised coordinates (origin bottom-left).
/// The points must be supplied in clockwise order starting from *top-left*.
public struct BoundingQuad {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// Returns `true` if the point lies inside the quad using the winding-number test.
    public func contains(_ p: CGPoint) -> Bool {
        let pts = [topLeft, topRight, bottomRight, bottomLeft]
        var wn = 0
        for i in 0..<4 {
            let p1 = pts[i]
            let p2 = pts[(i + 1) % 4]
            if p1.y <= p.y {
                if p2.y > p.y && isLeft(p1, p2, p) > 0 { wn += 1 }
            } else {
                if p2.y <= p.y && isLeft(p1, p2, p) < 0 { wn -= 1 }
            }
        }
        return wn != 0
    }
    
    /// Convenience CGPath for drawing.
    public var path: CGPath {
        let p = CGMutablePath()
        p.move(to: topLeft)
        p.addLine(to: topRight)
        p.addLine(to: bottomRight)
        p.addLine(to: bottomLeft)
        p.closeSubpath()
        return p
    }

    private func isLeft(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)
    }
} 
