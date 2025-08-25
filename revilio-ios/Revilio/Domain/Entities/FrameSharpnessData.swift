//
//  FrameSharpnessData.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Container for the per-cell sharpness metrics of a camera frame.
/// - `sharpnessGrid`: two-dimensional array `[row][column]` containing binary blur data for
///   every cell of the analysed grid where **true** marks a **sharp** cell.
/// The structure purposefully avoids storing the heavy `CMSampleBuffer` to eliminate
/// dangling references that could lead to premature memory deallocation when the
/// caller clears its buffers (e.g. via `removeAll()`).
public struct FrameSharpnessData {
    /// Indicates whether each cell of the analysed grid is sharp (`true`) or blurry (`false`).
    /// The first index is the row (top → bottom) and the second index is the column (left → right).
    public let sharpnessGrid: [[Bool]]
    /// Number of cells in `sharpnessGrid` that were classified as **sharp**.
    /// Exposed as a cached value so that callers can compare frames without re-iterating
    /// the entire grid every time.
    public let sharpCellCount: Int

    public init(sharpnessGrid: [[Bool]],
                sharpCellCount: Int) {
        self.sharpnessGrid = sharpnessGrid
        self.sharpCellCount = sharpCellCount
    }
}
