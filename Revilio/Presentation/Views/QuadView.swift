//
//  QuadView.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit

/// Simple reusable overlay that draws a quadrilateral path.
class QuadView {
    let shapeLayer: CAShapeLayer

    init() {
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 4
        shapeLayer.isHidden = true
    }

    func addToLayer(_ parent: CALayer) {
        parent.addSublayer(shapeLayer)
    }

    func show(quad: BoundingQuad, color: UIColor, alpha: CGFloat, in bounds: CGRect,
              transform: (_ p: CGPoint, _ bounds: CGRect) -> CGPoint) {
        CATransaction.setDisableActions(true)
        let tl = transform(quad.topLeft, bounds)
        let tr = transform(quad.topRight, bounds)
        let br = transform(quad.bottomRight, bounds)
        let bl = transform(quad.bottomLeft, bounds)
        let path = UIBezierPath()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.close()

        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.withAlphaComponent(alpha).cgColor
        shapeLayer.isHidden = false
    }

    func hide() { shapeLayer.isHidden = true }
} 
