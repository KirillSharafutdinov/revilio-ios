//
//  SharpnessKernels.metal
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

#include <metal_stdlib>
using namespace metal;

kernel void cellVar(
    texture2d<float, access::read>        lap          [[ texture(0) ]],
    texture2d<float, access::write>       outTex       [[ texture(1) ]],
    constant uint2 &                      cellSize     [[ buffer(0) ]],
    uint2                                 gid          [[ thread_position_in_grid ]])
{
    uint2 start = gid * cellSize;
    float mean = 0.0f;
    float m2   = 0.0f;
    uint  n    = 0u;

    for (uint y = 0u; y < cellSize.y; ++y) {
        for (uint x = 0u; x < cellSize.x; ++x) {
            float v = fabs(lap.read(uint2(start.x + x, start.y + y)).r * 255.0f); // * 255 for easy fine-tuning in sharpness service module
            n += 1u;
            float delta = v - mean;
            mean += delta / float(n);
            m2   += delta * (v - mean);
        }
    }
    float variance = (n > 1u) ? (m2 / float(n - 1u)) : 0.0f;
    outTex.write(variance, gid);
} 
