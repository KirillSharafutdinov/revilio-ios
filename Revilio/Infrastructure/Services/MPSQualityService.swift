//
//  MPSQualityService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreMedia
import CoreVideo
import Metal
import MetalKit
import MetalPerformanceShaders

/// GPU-accelerated implementation of `FrameQualityRepository` powered by Metal Performance Shaders.
/// The service evaluates the sharpness of a frame by computing the variance of the Laplacian
/// (VoL) on a configurable, **even-sized** grid of cells.
/// The function returns the sharpness data `FrameSharpnessData` of the frame cells (true = sharp),
/// comparing them with the sharpness threshold in Constants
final class MPSQualityService: FrameQualityRepository {
    // MARK: – Tunables
    /// Grid dimensions – configurable. Must be an **even** number to satisfy the current requirements.
    private let gridSize: Int = Constants.ReadText.gridSize
    /// Variance value that maps to a perfect score (blurScore = 0).  Higher variances are clamped.
    /// This keeps the [0;1] output range predictable regardless of outliers.
    private let mappingMaxVariance: Float = 256
    /// Maximum resolution (in pixels) of the longest image side that will be processed for the sharpness evaluation.
    /// Larger frames are down-sampled on the GPU using Lanczos scaling before the Laplacian is applied.
    private let maxLongSideForProcessing: Int = 1920
    
    // MARK: – Metal
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let laplacian: MPSImageLaplacian
    private var textureCache: CVMetalTextureCache!
    private let logger: Logger?
    /// Compute pipeline for per-cell variance reduction
    private let gridPipeline: MTLComputePipelineState
    
    // MARK: – Concurrency guard
    /// Ensures that only **one** frame is processed at a time for this `MPSQualityService` instance.
    /// Although Metal command queues are thread-safe, other shared resources (e.g. texture cache)
    /// and the cumulative GPU memory footprint may suffer from heavy parallelism.  Serialising
    /// the work eliminates race conditions and reduces peak memory usage.
    private let processingSemaphore = DispatchSemaphore(value: 1)
    
    // MARK: – Init
    init?(logger: Logger? = nil) {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        self.logger = logger
        self.device = dev
        guard let queue = dev.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.laplacian = MPSImageLaplacian(device: dev)

        // Compile compute kernel (cellVar)
        guard let defaultLib = dev.makeDefaultLibrary(),
              let kernelFn = defaultLib.makeFunction(name: "cellVar") else {
            return nil
        }
        do {
            self.gridPipeline = try dev.makeComputePipelineState(function: kernelFn)
        } catch {
            print("Failed to create compute pipeline: \(error)"); return nil
        }
        // Create a per-instance texture cache (faster than one global cache in multi-threaded contexts)
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, dev, nil, &cache)
        self.textureCache = cache!
    }
    
    // MARK: – Public API
    func evaluate(frame: CameraFrame) async -> FrameSharpnessData? {
        // Serialise access so that two concurrent tasks cannot evaluate simultaneously.
        // Using a semaphore instead of a serial queue keeps the async API intact.
        processingSemaphore.wait()
        defer { processingSemaphore.signal() }

        // Validate grid parameter once more to avoid division-by-zero or negative sizes.
        guard gridSize > 0, gridSize % 2 == 0 else {
            logger?.log(.error,
                        "MPSQualityService: Invalid gridSize \(gridSize). Must be positive and even.",
                        category: "FRAME_QUALITY",
                        file: #file,
                        function: #function,
                        line: #line)
            return nil
        }

        // Extract CMSampleBuffer from the opaque storage. If the cast fails
        // we cannot proceed with GPU evaluation.
        guard let sampleBuffer: CMSampleBuffer = frame.unwrap() else { return nil }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard width >= gridSize, height >= gridSize else { return nil }

        // Wrap GPU-heavy work in an autoreleasepool to mitigate memory spikes.
        return autoreleasepool { [self] in
            return performEvaluation(pixelBuffer: pixelBuffer,
                                      width: width,
                                      height: height)
        }
    }

    // MARK: – Internal evaluation pipeline
    private func performEvaluation(pixelBuffer: CVPixelBuffer,
                                   width: Int,
                                   height: Int) -> FrameSharpnessData? {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Create Metal texture from the pixel buffer
        guard let fullResTexture = makeTexture(from: pixelBuffer,
                                               pixelFormat: .bgra8Unorm,
                                               width: width,
                                               height: height) else { return nil }
        
        // ------------------------------------------------------------
        // 1. Optional down-scaling (GPU)
        // ------------------------------------------------------------
        let longestSide = max(width, height)
        var procTexture: MTLTexture = fullResTexture
        var procWidth: Int = width
        var procHeight: Int = height

        if longestSide > maxLongSideForProcessing {
            let scale = Float(maxLongSideForProcessing) / Float(longestSide)
            procWidth = Int(Float(width) * scale)
            procHeight = Int(Float(height) * scale)

            let scaleDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fullResTexture.pixelFormat,
                                                                     width: procWidth,
                                                                     height: procHeight,
                                                                     mipmapped: false)
            scaleDesc.usage = [.shaderRead, .shaderWrite]
            guard let scaledTex = device.makeTexture(descriptor: scaleDesc) else { return nil }

            guard let scaleCmd = commandQueue.makeCommandBuffer() else { return nil }
            let lanczos = MPSImageLanczosScale(device: device)
            lanczos.encode(commandBuffer: scaleCmd,
                           sourceTexture: fullResTexture,
                           destinationTexture: scaledTex)
            scaleCmd.commit()
            scaleCmd.waitUntilCompleted()

            procTexture = scaledTex
        }

        // ------------------------------------------------------------
        // 2. Laplacian (GPU) on possibly down-scaled texture
        // ------------------------------------------------------------
        let lapDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: procTexture.pixelFormat,
                                                               width: procWidth,
                                                               height: procHeight,
                                                               mipmapped: false)
        lapDesc.usage = [.shaderRead, .shaderWrite]
        guard let lapTexture = device.makeTexture(descriptor: lapDesc) else { return nil }

        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return nil }
        laplacian.encode(commandBuffer: cmdBuffer,
                         sourceTexture: procTexture,
                         destinationTexture: lapTexture)
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // ------------------------------------------------------------
        // 3. GPU reduction – one thread per grid cell -> r32Float gridTex
        // ------------------------------------------------------------
        // Ensure non-zero cell dimensions even in edge-cases (should be guaranteed by earlier guard).
        let cellWidth = max(1, procWidth / gridSize)
        let cellHeight = max(1, procHeight / gridSize)

        let gridDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                width: gridSize,
                                                                height: gridSize,
                                                                mipmapped: false)
        gridDesc.usage = [.shaderWrite]
        guard let gridTex = device.makeTexture(descriptor: gridDesc) else { return nil }

        guard let reduceCmd = commandQueue.makeCommandBuffer(),
              let encoder = reduceCmd.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(gridPipeline)
        encoder.setTexture(lapTexture, index: 0)
        encoder.setTexture(gridTex, index: 1)
        var cs = simd_uint2(UInt32(cellWidth), UInt32(cellHeight))
        encoder.setBytes(&cs, length: MemoryLayout<simd_uint2>.stride, index: 0)

        let tgWidth = gridPipeline.threadExecutionWidth
        let tgHeight = gridPipeline.maxTotalThreadsPerThreadgroup / tgWidth
        let threadsPerThreadgroup = MTLSize(width: tgWidth, height: tgHeight, depth: 1)
        let threadsPerGrid = MTLSize(width: gridSize, height: gridSize, depth: 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        reduceCmd.commit()
        reduceCmd.waitUntilCompleted()

        // ------------------------------------------------------------
        // 4. Read back the tiny 60×60 grid
        // ------------------------------------------------------------
        let bytesPerPixel = 4
        let bytesPerRow = gridSize * bytesPerPixel
        var gridRaw = [Float](repeating: 0, count: gridSize * gridSize)
        let gridRegion = MTLRegionMake2D(0, 0, gridSize, gridSize)
        gridTex.getBytes(&gridRaw,
                         bytesPerRow: bytesPerRow,
                         from: gridRegion,
                         mipmapLevel: 0)

        // Convert the raw variances to a **boolean** sharpness map.
        // A cell is considered sharp if its normalised blur score is below or equal
        // to the global `blurScoreThreshold` value.
        var sharpnessGrid: [[Bool]] = Array(repeating: Array(repeating: false, count: gridSize),
                                            count: gridSize)

        let threshold = Constants.ReadText.blurScoreThreshold
        var sharpCellCount = 0
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let idx = y * gridSize + x
                let varLap = gridRaw[idx]
                let cellBlur = max(0.0, 1.0 - min(varLap, mappingMaxVariance) / mappingMaxVariance)
                let isSharp = cellBlur <= threshold
                sharpnessGrid[y][x] = isSharp
                if isSharp { sharpCellCount += 1 }
            }
        }
        
        let data = FrameSharpnessData(sharpnessGrid: sharpnessGrid,
                                      sharpCellCount: sharpCellCount)

        if let logger {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            logger.log(.info,
                       String(format: "MPSQualityService: evaluation finished in %.1f ms", elapsed),
                       category: "FRAME_QUALITY",
                       file: #file,
                       function: #function,
                       line: #line)
        }

        return data
    }
    
    // MARK: – Helpers
    private func makeTexture(from pixelBuffer: CVPixelBuffer,
                              pixelFormat: MTLPixelFormat,
                              width: Int,
                              height: Int) -> MTLTexture? {
        var cvTextureOut: CVMetalTexture?
        let res = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                            textureCache,
                                                            pixelBuffer,
                                                            nil,
                                                            pixelFormat,
                                                            width,
                                                            height,
                                                            0,
                                                            &cvTextureOut)
        if res != kCVReturnSuccess { return nil }
        guard let cvTexture = cvTextureOut else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
} 
