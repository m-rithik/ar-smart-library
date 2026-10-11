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

enum DepthSampler {
    static func measurement(in frame: ARFrame, at imagePoint: CGPoint) -> SpatialMeasurement? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            return nil
        }

        let depthMap = depthData.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let sampleX = min(max(Int(imagePoint.x * CGFloat(width)), 0), width - 1)
        let sampleY = min(max(Int(imagePoint.y * CGFloat(height)), 0), height - 1)

        guard
            let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap),
            CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32
        else {
            return nil
        }

        let depthRow = depthBaseAddress
            .advanced(by: sampleY * CVPixelBufferGetBytesPerRow(depthMap))
            .assumingMemoryBound(to: Float32.self)
        let depth = depthRow[sampleX]

        guard depth.isFinite, (0.15 ... 5.0).contains(depth) else {
            return nil
        }

        let confidence = confidenceLevel(atX: sampleX, y: sampleY, in: depthData.confidenceMap)
        let quality: SpatialQuality = confidence >= 2 ? .high : .medium

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

        let imageX = Float(sampleX)
        let imageY = Float(sampleY)
        let cameraX = (imageX - principalX) * depth / focalX
        let cameraY = (imageY - principalY) * depth / focalY
        let cameraPoint = SIMD4<Float>(cameraX, -cameraY, -depth, 1)
        let worldPoint = frame.camera.transform * cameraPoint

        return SpatialMeasurement(
            position: SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z),
            quality: quality
        )
    }

    private static func confidenceLevel(atX x: Int, y: Int, in confidenceMap: CVPixelBuffer?) -> Int {
        guard let confidenceMap else {
            return 1
        }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return 1
        }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        let boundedX = min(max(x, 0), width - 1)
        let boundedY = min(max(y, 0), height - 1)
        let row = baseAddress
            .advanced(by: boundedY * CVPixelBufferGetBytesPerRow(confidenceMap))
            .assumingMemoryBound(to: UInt8.self)
        return Int(row[boundedX])
    }
}
