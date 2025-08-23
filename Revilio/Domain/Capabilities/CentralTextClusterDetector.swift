//
//  CentralTextClusterDetector.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Grid cell structure for text clustering
struct GridCell {
    let row: Int
    let col: Int
    var hasText: Bool = false
    
    init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}
/// A self-contained helper that implements the concentric-ring cluster algorithm.
/// The detector works purely on a boolean grid where `true` marks a cell that
/// contains recognised text.  All coordinates are expressed in *grid indices*
/// (row-major, origin at the **top-left**).  The resulting rectangle is returned
/// in Vision normalised coordinates (origin at the **bottom-left**, range [0,1]).
struct CentralTextClusterDetector {
    private let grid: [[Bool]]
    private let rows: Int
    private let cols: Int
    private let emptyThreshold: CGFloat
    private let vertGap: Int
    private let horizGap: Int
    private let diagDegreeStep: CGFloat
    private let diagSteps: Int
    // Threshold for base cluster expansion (rows/cols with < threshold emptiness are included).
    private let baseFillEmptyThreshold: CGFloat
    private let logFn: (String)->Void

    init(grid: [[Bool]],
         emptyThreshold: CGFloat,
         vertGap: Int,
         horizGap: Int,
         diagDegreeStep: CGFloat,
         diagSteps: Int,
         baseFillEmptyThreshold: CGFloat = Constants.ReadText.clusterBaseFillEmptyThreshold,
         log: @escaping (String)->Void = {_ in}) {
        self.grid = grid
        self.rows = grid.count
        self.cols = grid.first?.count ?? 0
        self.emptyThreshold = emptyThreshold
        self.vertGap = max(1, vertGap)
        self.horizGap = max(1, horizGap)
        self.diagDegreeStep = diagDegreeStep
        self.diagSteps = diagSteps
        self.baseFillEmptyThreshold = baseFillEmptyThreshold
        self.logFn = log
    }

    /// Entry point – returns a rectangle in Vision coordinate space or `nil` if no text.
    func detect() -> BoundingQuad? {
        // Saves boundary information as (central cell, angle)
        // and computes the bounding quad from the intersections of the resulting
        // four infinite lines.

        guard rows > 0, cols > 0, let seed = nearestCentralCell() else { return nil }

        logFn("SEED cell at (row:\(seed.r), col:\(seed.c))")

        //------------------------------------------------------------------
        // 1. Strict outward growth – build the *base* cluster (same as before)
        //------------------------------------------------------------------
        var minR = seed.r, maxR = seed.r, minC = seed.c, maxC = seed.c
        var canGrowUp = true, canGrowDown = true, canGrowLeft = true, canGrowRight = true

        while canGrowUp || canGrowDown || canGrowLeft || canGrowRight {
            if canGrowUp   { canGrowUp   = growUp(&minR,   minC: minC, maxC: maxC) }
            if canGrowDown { canGrowDown = growDown(&maxR, minC: minC, maxC: maxC) }
            if canGrowLeft { canGrowLeft = growLeft(&minC, minR: minR, maxR: maxR) }
            if canGrowRight{ canGrowRight = growRight(&maxC,minR: minR, maxR: maxR) }
        }

        logFn("BASE cluster rows \(minR)...\(maxR) cols \(minC)...\(maxC)")

        //------------------------------------------------------------------
        // 2. Helper – best emptiness for a column strip incl. diagonal variants
        //------------------------------------------------------------------
        func bestEmptyRatioForCols(c0: Int, c1: Int, r0: Int, r1: Int) -> (ratio: CGFloat, angle: CGFloat) {
            guard c0 >= 0, c1 < cols else { return (1.0, 90) }

            // Base (vertical) strip.
            var maxEmpty: CGFloat = _emptyRatioCols(c0: c0, c1: c1, r0: r0, r1: r1)
            var bestAngle: CGFloat = 90 // vertical → 90° relative to horizontal.

            // Diagonal variants.
            let h = r1 - r0 + 1
            guard diagSteps > 0 else { return (maxEmpty, bestAngle) }

            for s in 1...diagSteps {
                let stepDeg = diagDegreeStep * CGFloat(s)
                let angRad  = stepDeg * (.pi / 180)
                let totalShift = tan(angRad) * CGFloat(h)
                let halfShift  = Int(round(totalShift / 2))

                for sign in [-1, 1] {
                    let shift = halfShift * sign
                    let ratio = _emptyRatioDiag(c0: c0, c1: c1, r0: r0, r1: r1, shift: shift)
                    let absAngle = 90 + stepDeg * CGFloat(sign) // 88…92° range.
                    if ratio > maxEmpty {
                        maxEmpty = ratio
                        bestAngle = absAngle
                    }
                }
            }
            return (maxEmpty, bestAngle)
        }

        //------------------------------------------------------------------
        // 3. Boundary-line descriptor
        //------------------------------------------------------------------
        struct BoundaryLine {
            let row: Int   // central **row** of the empty strip (grid coords)
            let col: Int   // central **col** of the empty strip (grid coords)
            let angle: CGFloat // rotation angle in *degrees* relative to horizontal.
        }

        //------------------------------------------------------------------
        // 4. Detect the four boundaries (top / bottom / left / right)
        //------------------------------------------------------------------

        // TOP ----------------------------------------------------------------
        var top: BoundaryLine? = nil
        var probeR = minR - 1 // start just above the current cluster
        while probeR - vertGap + 1 >= 0 {
            let r0 = probeR - vertGap + 1
            let r1 = probeR
            let ratio = emptyRatioRows(r0: r0, r1: r1, c0: minC, c1: maxC)
            logFn(String(format: "SCAN TOP rows %d‒%d empty=%.2f", probeR, probeR + vertGap - 1, Double(ratio)))
            if ratio >= emptyThreshold {
                top = BoundaryLine(row: r0 + vertGap / 2,
                                   col: (minC + maxC) / 2,
                                   angle: 0)
                break
            }
            probeR -= 1 // slide window up by one row
        }
        if top == nil {
            top = BoundaryLine(
                row: 0,
                col: (minC + maxC) / 2,
                angle: 0
            )
            logFn("TOP boundary fallback to FRAME EDGE (row:0)")
        }

        // BOTTOM -------------------------------------------------------------
        var bottom: BoundaryLine? = nil
        probeR = maxR + vertGap // start one full gap below cluster bottom (consistent with old behaviour)
        while probeR < rows {
            let r0 = probeR - vertGap + 1
            let r1 = probeR
            guard r0 >= maxR + 1 else { probeR += 1; continue }
            if r1 >= rows { break }
            let ratio = emptyRatioRows(r0: r0, r1: r1, c0: minC, c1: maxC)
            logFn(String(format: "SCAN BOTTOM rows %d‒%d empty=%.2f", probeR, probeR + vertGap - 1, Double(ratio)))
            if ratio >= emptyThreshold {
                bottom = BoundaryLine(row: r0 + vertGap / 2,
                                      col: (minC + maxC) / 2,
                                      angle: 0)
                break
            }
            probeR += 1 // slide window down by one row
        }
        if bottom == nil {
            bottom = BoundaryLine(
                row: rows - 1,
                col: (minC + maxC) / 2,
                angle: 0
            )
            logFn("BOTTOM boundary fallback to FRAME EDGE (row:\(rows-1))")
        }

        // LEFT --------------------------------------------------------------
        var left: BoundaryLine? = nil
        var probeC = minC - 1
        while probeC - horizGap + 1 >= 0 {
            let c0 = probeC - horizGap + 1
            let c1 = probeC
            let (ratio, bestAngle) = bestEmptyRatioForCols(c0: c0, c1: c1,
                                                            r0: minR, r1: maxR)
            logFn(String(format: "SCAN LEFT cols %d‒%d empty=%.2f angle=%.0f°", probeC, probeC + horizGap - 1, Double(ratio), Double(bestAngle)))
            if ratio >= emptyThreshold {
                left = BoundaryLine(row: (minR + maxR) / 2,
                                    col: c0 + horizGap / 2,
                                    angle: bestAngle)
                break
            }
            probeC -= 1
        }
        if left == nil {
            left = BoundaryLine(
                row: (minR + maxR) / 2,
                col: 0,
                angle: 90
            )
            logFn("LEFT boundary fallback to FRAME EDGE (col:0)")
        }

        // RIGHT -------------------------------------------------------------
        var right: BoundaryLine? = nil
        probeC = maxC + horizGap
        while probeC < cols {
            let c0 = probeC - horizGap + 1
            let c1 = probeC
            guard c0 >= maxC + 1 else { probeC += 1; continue }
            let (ratio, bestAngle) = bestEmptyRatioForCols(c0: c0, c1: c1,
                                                            r0: minR, r1: maxR)
            logFn(String(format: "SCAN RIGHT cols %d‒%d empty=%.2f angle=%.0f°", probeC, probeC + horizGap - 1, Double(ratio), Double(bestAngle)))
            if ratio >= emptyThreshold {
                right = BoundaryLine(row: (minR + maxR) / 2,
                                     col: c0 + horizGap / 2,
                                      angle: bestAngle)
                break
            }
            probeC += 1
        }
        if right == nil {
            right = BoundaryLine(
                row: (minR + maxR) / 2,
                col: cols - 1,
                angle: 90
            )
            logFn("RIGHT boundary fallback to FRAME EDGE (col:\(cols-1))")
        }

        //------------------------------------------------------------------
        // 5. Log the captured boundaries in the required format
        //------------------------------------------------------------------
        if let t = top    { logFn(String(format: "BOUNDARY TOP    (row:%d,col:%d), angle:%.0f°",    t.row, t.col, Double(t.angle))) }
        if let b = bottom { logFn(String(format: "BOUNDARY BOTTOM (row:%d,col:%d), angle:%.0f°",    b.row, b.col, Double(b.angle))) }
        if let l = left   { logFn(String(format: "BOUNDARY LEFT   (row:%d,col:%d), angle:%.0f°",    l.row, l.col, Double(l.angle))) }
        if let r = right  { logFn(String(format: "BOUNDARY RIGHT  (row:%d,col:%d), angle:%.0f°",    r.row, r.col, Double(r.angle))) }

        guard let tB = top, let bB = bottom, let lB = left, let rB = right else { return nil }

        //------------------------------------------------------------------
        // 6. Convert boundaries to Vision-normalised coordinates first
        //------------------------------------------------------------------
        func toVision(row: Int, col: Int) -> CGPoint {
            let x = CGFloat(col) / CGFloat(cols)
            let y = (CGFloat(rows - 1 - row)) / CGFloat(rows)
            return CGPoint(x: x, y: y)
        }

        struct NormBoundary {
            let p: CGPoint  // point on line (Vision coords)
            let angle: CGFloat // degrees, 0 = horizontal, 90 = vertical
            var isVertical: Bool { abs(angle - 90) < 1.0 }
        }

        let topN    = NormBoundary(p: toVision(row: tB.row, col: tB.col), angle: tB.angle)
        let bottomN = NormBoundary(p: toVision(row: bB.row, col: bB.col), angle: bB.angle)
        let leftN   = NormBoundary(p: toVision(row: lB.row, col: lB.col), angle: lB.angle)
        let rightN  = NormBoundary(p: toVision(row: rB.row, col: rB.col), angle: rB.angle)

        //------------------------------------------------------------------
        // 7. Intersection helpers in Vision coords
        //------------------------------------------------------------------
        func slope(of line: NormBoundary) -> CGFloat? {
            if line.isVertical { return nil } // infinite
            return tan(line.angle * .pi / 180)
        }

        func intersection(_ a: NormBoundary, _ b: NormBoundary) -> CGPoint {
            // Handle vertical × non-vertical and vertical × horizontal cases directly
            if a.isVertical, !b.isVertical {
                let mB = slope(of: b)!
                let x = a.p.x
                let y = mB * (x - b.p.x) + b.p.y
                return CGPoint(x: x, y: y)
            }
            if b.isVertical, !a.isVertical {
                return intersection(b, a) // reuse logic swapping
            }
            // Horizontal (slope 0) × non-vertical
            if abs(a.angle) < 1.0, !b.isVertical {
                let y = a.p.y
                let mB = slope(of: b)!
                let x = (y - b.p.y) / mB + b.p.x
                return CGPoint(x: x, y: y)
            }
            if abs(b.angle) < 1.0, !a.isVertical {
                return intersection(b, a)
            }
            // Fallback general case – solve two slopes.
            let mA = slope(of: a)!
            let mB = slope(of: b)!
            let x = (mA * a.p.x - mB * b.p.x + b.p.y - a.p.y) / (mA - mB)
            let y = mA * (x - a.p.x) + a.p.y
            return CGPoint(x: x, y: y)
        }

        let tl = intersection(leftN,  topN)
        let tr = intersection(rightN, topN)
        let bl = intersection(leftN,  bottomN)
        let br = intersection(rightN, bottomN)

        logFn("Quad TL\(tl) TR\(tr) BR\(br) BL\(bl)")

        return BoundingQuad(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }
    
    // MARK: – Seed search --------------------------------------------------
    private func nearestCentralCell() -> (r: Int, c: Int)? {
        let centerR = rows / 2
        let centerC = cols / 2
        var best: (Int, Int)? = nil
        var bestDist = Double.greatestFiniteMagnitude

        for r in 0..<rows {
            for c in 0..<cols where grid[r][c] {
                let d = hypot(Double(r - centerR), Double(c - centerC))
                if d < bestDist {
                    bestDist = d
                    best = (r, c)
                }
            }
        }
        return best
    }

    // MARK: – Strict ring growth helpers ----------------------------------
    // Ring growth tolerates partially empty rows/columns. We grow if the
    // *emptiness ratio* across the candidate strip is below `emptyThreshold`.
    // This allows bridging small gaps between lines of text.

    private func growUp(_ minR: inout Int, minC: Int, maxC: Int) -> Bool {
        guard minR > 0 else { return false }
        let candidate = minR - 1
        let empty = _emptyRatioRows(r0: candidate, r1: candidate, c0: minC, c1: maxC)
        guard empty < baseFillEmptyThreshold else { return false }
        minR = candidate; return true
    }

    private func growDown(_ maxR: inout Int, minC: Int, maxC: Int) -> Bool {
        guard maxR + 1 < rows else { return false }
        let candidate = maxR + 1
        let empty = _emptyRatioRows(r0: candidate, r1: candidate, c0: minC, c1: maxC)
        guard empty < baseFillEmptyThreshold else { return false }
        maxR = candidate; return true
    }

    private func growLeft(_ minC: inout Int, minR: Int, maxR: Int) -> Bool {
        guard minC > 0 else { return false }
        let candidate = minC - 1
        let empty = _emptyRatioCols(c0: candidate, c1: candidate, r0: minR, r1: maxR)
        guard empty < baseFillEmptyThreshold else { return false }
        minC = candidate; return true
    }

    private func growRight(_ maxC: inout Int, minR: Int, maxR: Int) -> Bool {
        guard maxC + 1 < cols else { return false }
        let candidate = maxC + 1
        let empty = _emptyRatioCols(c0: candidate, c1: candidate, r0: minR, r1: maxR)
        guard empty < baseFillEmptyThreshold else { return false }
        maxC = candidate; return true
    }

    /// Convenience wrapper that reuses the multi-row helper for a single row.
    private func _emptyRatioRows(r0: Int, r1: Int, c0: Int, c1: Int) -> CGFloat {
        return emptyRatioRows(r0: r0, r1: r1, c0: c0, c1: c1)
    }

    // MARK: – Gap-tolerant strip analytics --------------------------------
    private func emptyRatioRows(r0: Int, r1: Int, c0: Int, c1: Int) -> CGFloat {
        guard r0 >= 0, r1 < rows else { return 1.0 }
        let totalCells = (r1 - r0 + 1) * (c1 - c0 + 1)
        var filled = 0
        for r in r0...r1 {
            for c in c0...c1 where grid[r][c] { filled += 1 }
        }
        return CGFloat(totalCells - filled) / CGFloat(totalCells)
    }

    /// Calculates the highest emptiness ratio across the straight strip plus several
    /// shallow diagonal variants determined by `diagDegreeStep` and `diagSteps`.
    private func emptyRatioCols(c0: Int, c1: Int, r0: Int, r1: Int) -> CGFloat {
        guard c0 >= 0, c1 < cols else { return 1.0 }

        let baseRatio: CGFloat = _emptyRatioCols(c0: c0, c1: c1, r0: r0, r1: r1)
        logFn(String(format: "    ▶︎ Base strip (%d‒%d) empty=%.2f", c0, c1, Double(baseRatio)))

        // Pre-compute max emptiness across all tested diagonals.
        var maxEmpty = baseRatio

        // Height of strip in rows.
        let h = r1 - r0 + 1
        guard diagSteps > 0 else { return maxEmpty }

        let degStep = diagDegreeStep
        for s in 1...diagSteps {
            let ang = degStep * CGFloat(s) * (.pi / 180.0)
            // Lateral shift across the **whole** column height for a given angle.
            // When rotating around the *central* cell we need only half of that range
            // (top goes -Δ, bottom goes +Δ).
            let totalShift = tan(ang) * CGFloat(h)
            let halfShift = Int(round(totalShift / 2))

            for sign in [-1, 1] {
                let shift = halfShift * sign
                let ratio = _emptyRatioDiag(c0: c0, c1: c1, r0: r0, r1: r1, shift: shift)
                let signedAngle = degStep * CGFloat(s) * CGFloat(sign)
                logFn(String(format: "    ▶︎ Diag shift %+d (angle %.0f°) empty=%.2f", shift, Double(signedAngle), Double(ratio)))
                if ratio > maxEmpty { maxEmpty = ratio }
            }
        }
        logFn(String(format: "    ▶︎ Max empty across variants = %.2f", Double(maxEmpty)))
        return maxEmpty
    }

    /// Straight column emptiness helper.
    private func _emptyRatioCols(c0: Int, c1: Int, r0: Int, r1: Int) -> CGFloat {
        let totalCells = (c1 - c0 + 1) * (r1 - r0 + 1)
        var filled = 0
        for c in c0...c1 {
            for r in r0...r1 where grid[r][c] { filled += 1 }
        }
        return CGFloat(totalCells - filled) / CGFloat(totalCells)
    }

    /// Diagonal variant: samples one cell per row following a linear offset.
    private func _emptyRatioDiag(c0: Int, c1: Int, r0: Int, r1: Int, shift: Int) -> CGFloat {
        let height = r1 - r0 + 1
        guard height > 0 else { return 1.0 }

        // The *pivot* (axis of rotation) is the central row of the strip.
        let pivot = CGFloat(height - 1) / 2.0

        var filled = 0
        var considered = 0

        for rowOffset in 0..<height {
            let r = r0 + rowOffset

            // Normalised distance from pivot in range [-1, +1].
            let rel = (CGFloat(rowOffset) - pivot) / max(1, pivot)
            let colShift = Int(round(rel * CGFloat(shift)))

            for baseC in c0...c1 {
                let c = baseC + colShift
                guard c >= 0 && c < cols else { continue }
                considered += 1
                if grid[r][c] { filled += 1 }
            }
        }

        guard considered > 0 else { return 1.0 }
        return CGFloat(considered - filled) / CGFloat(considered)
    }
}
