import ARKit
import CoreVideo
import simd

enum SpatialQuality: Comparable {
    case unavailable
    case medium
    case high
}

struct SpatialMeasurement {
    let position: SIMD3<Float>
    let quality: SpatialQuality
}

struct DepthSample {
    let depth: Float
    let quality: SpatialQuality
}

enum DepthSampler {
    static func measurement(in frame: ARFrame, at imagePoint: CGPoint) -> SpatialMeasurement? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let sample = sample(in: depthData.depthMap, confidenceMap: depthData.confidenceMap, at: imagePoint) else {
            return nil
        }

        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let imageResolution = frame.camera.imageResolution
        let scaleX = Float(width) / Float(imageResolution.width)
        let scaleY = Float(height) / Float(imageResolution.height)
        let intrinsics = frame.camera.intrinsics
        let focalX = intrinsics.columns.0.x * scaleX
        let focalY = intrinsics.columns.1.y * scaleY
        let principalX = intrinsics.columns.2.x * scaleX
        let principalY = intrinsics.columns.2.y * scaleY

        guard focalX > 0, focalY > 0 else {
            return nil
        }

        let imageX = min(Float(imagePoint.x) * Float(width), Float(width - 1))
        let imageY = min(Float(imagePoint.y) * Float(height), Float(height - 1))
        let cameraX = (imageX - principalX) * sample.depth / focalX
        let cameraY = (imageY - principalY) * sample.depth / focalY
        let cameraPoint = SIMD4<Float>(cameraX, -cameraY, -sample.depth, 1)
        let worldPoint = frame.camera.transform * cameraPoint

        return SpatialMeasurement(
            position: SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z),
            quality: sample.quality
        )
    }

    static func sample(in depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?, at imagePoint: CGPoint) -> DepthSample? {
        guard imagePoint.x.isFinite, imagePoint.y.isFinite,
              (0...1).contains(imagePoint.x), (0...1).contains(imagePoint.y),
              CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else { return nil }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }
        if let confidenceMap {
            guard CVPixelBufferGetWidth(confidenceMap) == width,
                  CVPixelBufferGetHeight(confidenceMap) == height,
                  CVPixelBufferGetPixelFormatType(confidenceMap) == kCVPixelFormatType_OneComponent8 else { return nil }
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
        defer { if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) } }
        guard let depthAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let confidenceAddress = confidenceMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        if confidenceMap != nil, confidenceAddress == nil { return nil }
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let x = min(Int(imagePoint.x * CGFloat(width)), width - 1)
        let y = min(Int(imagePoint.y * CGFloat(height)), height - 1)
        let columns = max(0, x - 1)...min(width - 1, x + 1)
        let rows = max(0, y - 1)...min(height - 1, y + 1)
        let minimumSupport = min(5, columns.count * rows.count)
        var samples: [(depth: Float, confidence: UInt8)] = []
        for rowIndex in rows {
            let depthRow = depthAddress.advanced(by: rowIndex * CVPixelBufferGetBytesPerRow(depthMap))
                .assumingMemoryBound(to: Float32.self)
            let confidenceRow = confidenceAddress.map {
                $0.advanced(by: rowIndex * confidenceStride)
                    .assumingMemoryBound(to: UInt8.self)
            }
            for column in columns {
                let depth = depthRow[column]
                let confidence = confidenceRow?[column] ?? 1
                if depth.isFinite, (0.15...5).contains(depth), (1...2).contains(confidence) {
                    samples.append((depth, confidence))
                }
            }
        }
        guard samples.count >= minimumSupport else { return nil }
        samples.sort { $0.depth < $1.depth }
        let median = samples[samples.count / 2].depth
        let tolerance = max(0.03, median * 0.02)
        let coherent = samples.filter { abs($0.depth - median) <= tolerance }
        // A small outlier is recoverable; mixed foreground/background surfaces are not.
        guard coherent.count >= minimumSupport, coherent.count * 4 >= samples.count * 3 else { return nil }
        let quality: SpatialQuality = coherent.filter { $0.confidence == 2 }.count * 4 >= coherent.count * 3
            ? .high : .medium

        return DepthSample(depth: coherent[coherent.count / 2].depth, quality: quality)
    }
}
