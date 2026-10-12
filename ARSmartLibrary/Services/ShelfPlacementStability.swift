import Foundation
import simd

struct ShelfPlacementStability {
    private(set) var stableTransform: simd_float4x4?
    private var firstTransform: simd_float4x4?
    private var lastTransform: simd_float4x4?
    private var startedAt: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var depthOnly: Bool?
    private var observationCount = 0

    @discardableResult
    mutating func observe(_ transform: simd_float4x4?, at timestamp: TimeInterval, isDepthOnly: Bool = false) -> Bool {
        guard let transform, timestamp.isFinite, Self.isRigid(transform) else {
            reset()
            return false
        }
        if lastTimestamp == timestamp {
            guard depthOnly == isDepthOnly, let lastTransform,
                  (0..<4).allSatisfy({ transform[$0] == lastTransform[$0] }) else {
                reset()
                return false
            }
            return stableTransform != nil
        }
        let continues = depthOnly == isDepthOnly
            && lastTimestamp.map { timestamp > $0 && timestamp - $0 <= 0.3 } == true
            && firstTransform.map { Self.isClose(transform, to: $0) } == true
            && lastTransform.map { Self.isClose(transform, to: $0) } == true
        if !continues {
            reset()
            firstTransform = transform
            startedAt = timestamp
            depthOnly = isDepthOnly
        }
        lastTransform = transform
        lastTimestamp = timestamp
        observationCount += 1
        let ready = observationCount >= 4 && timestamp - (startedAt ?? timestamp) >= 0.5
        stableTransform = ready ? transform : nil
        return ready
    }

    mutating func reset() {
        stableTransform = nil
        firstTransform = nil
        lastTransform = nil
        startedAt = nil
        lastTimestamp = nil
        depthOnly = nil
        observationCount = 0
    }

    private static func isClose(_ transform: simd_float4x4, to reference: simd_float4x4) -> Bool {
        let offset = transform.columns.3 - reference.columns.3
        let similarity = min(1, abs(simd_dot(simd_quatf(transform).vector, simd_quatf(reference).vector)))
        return simd_length(offset) <= 0.05 && 2 * acos(similarity) <= .pi / 18
    }

    private static func isRigid(_ transform: simd_float4x4) -> Bool {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { transform[column][$0].isFinite } }) else { return false }
        let rotation = simd_float3x3(columns: (
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        ))
        return abs(transform.columns.0.w) < 0.01 && abs(transform.columns.1.w) < 0.01
            && abs(transform.columns.2.w) < 0.01 && abs(transform.columns.3.w - 1) < 0.01
            && (0..<3).allSatisfy { abs(simd_length(rotation[$0]) - 1) < 0.01 }
            && abs(simd_dot(rotation[0], rotation[1])) < 0.01
            && abs(simd_dot(rotation[0], rotation[2])) < 0.01
            && abs(simd_dot(rotation[1], rotation[2])) < 0.01
            && simd_determinant(rotation) > 0.99
    }
}
