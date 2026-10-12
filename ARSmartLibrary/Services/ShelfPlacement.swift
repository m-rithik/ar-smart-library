import simd

enum ShelfPlacement {
    /// Shelf outlines use local XY, with +Z facing away from the shelf toward its reader.
    static func transform(
        at point: SIMD3<Float>,
        cameraPosition: SIMD3<Float>,
        surfaceNormal: SIMD3<Float>?
    ) -> simd_float4x4? {
        guard isFinite(point), isFinite(cameraPosition) else { return nil }
        let outward = SIMD3<Float>(cameraPosition.x - point.x, 0, cameraPosition.z - point.z)
        let cameraDistance = simd_length(outward)
        guard cameraDistance.isFinite, cameraDistance >= 0.15 else { return nil }

        var normal: SIMD3<Float>
        if let surfaceNormal {
            guard isFinite(surfaceNormal) else { return nil }
            let surfaceLength = simd_length(surfaceNormal)
            // A floor or shelf top must not become an upright row after flattening its normal.
            guard surfaceLength > 0.001, abs(surfaceNormal.y) / surfaceLength < 0.35 else { return nil }
            normal = SIMD3(surfaceNormal.x, 0, surfaceNormal.z)
            let length = simd_length(normal)
            guard length.isFinite, length > 0.001 else { return nil }
            normal /= length
            if simd_dot(normal, outward) < 0 { normal = -normal }
        } else {
            normal = outward / cameraDistance
        }

        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(up, normal))
        return simd_float4x4(columns: (
            SIMD4(right, 0), SIMD4(up, 0), SIMD4(normal, 0), SIMD4(point, 1)
        ))
    }

    private static func isFinite(_ point: SIMD3<Float>) -> Bool {
        (0..<3).allSatisfy { point[$0].isFinite }
    }
}
