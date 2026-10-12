import simd
import XCTest
@testable import ARSmartLibrary

final class ShelfPlacementStabilityTests: XCTestCase {
    func testRequiresFourReadingsAndHalfASecondThenUsesLatestCandidate() throws {
        var stability = ShelfPlacementStability()
        XCTAssertFalse(stability.observe(transform(), at: 1))
        XCTAssertFalse(stability.observe(transform(x: 0.01), at: 1.1))
        XCTAssertFalse(stability.observe(transform(x: 0.02), at: 1.2))
        XCTAssertFalse(stability.observe(transform(x: 0.03), at: 1.3))
        XCTAssertTrue(stability.observe(transform(x: 0.04, degrees: 5), at: 1.5))

        let ready = try XCTUnwrap(stability.stableTransform)
        XCTAssertEqual(ready.columns.3.x, 0.04, accuracy: 0.001)
        XCTAssertEqual(ready.columns.2.x, sin(Float.pi / 36), accuracy: 0.001)
    }

    func testRepeatedFrameDoesNotAddEvidenceAndReadyFrameCanBeConfirmed() {
        var stability = ShelfPlacementStability()
        XCTAssertFalse(stability.observe(transform(), at: 1))
        XCTAssertFalse(stability.observe(transform(), at: 1.25))
        XCTAssertFalse(stability.observe(transform(), at: 1.5))
        XCTAssertFalse(stability.observe(transform(), at: 1.5))
        XCTAssertTrue(stability.observe(transform(), at: 1.6))
        XCTAssertTrue(stability.observe(transform(), at: 1.6))

        XCTAssertFalse(stability.observe(transform(x: 0.01), at: 1.6))
        XCTAssertNil(stability.stableTransform)
    }

    func testPositionJumpAndRotationChangeResetReadiness() {
        for changed in [transform(x: 0.06), transform(degrees: 11)] {
            var stability = readyStability()
            XCTAssertFalse(stability.observe(changed, at: 1.8))
            XCTAssertNil(stability.stableTransform)
        }
    }

    func testGradualMovementCannotAccumulatePastTheOriginalCandidate() {
        var stability = ShelfPlacementStability()
        for index in 0..<5 {
            XCTAssertFalse(stability.observe(transform(x: Float(index) * 0.02), at: 1 + Double(index) * 0.15))
        }
        XCTAssertNil(stability.stableTransform)
    }

    func testLossSourceChangeGapAndOlderFrameResetReadiness() {
        var loss = readyStability()
        XCTAssertFalse(loss.observe(nil, at: 1.8))
        XCTAssertNil(loss.stableTransform)
        XCTAssertFalse(loss.observe(transform(), at: 1.9))

        var source = readyStability()
        XCTAssertFalse(source.observe(transform(), at: 1.8, isDepthOnly: true))
        XCTAssertNil(source.stableTransform)

        var gap = readyStability()
        XCTAssertFalse(gap.observe(transform(), at: 2))
        XCTAssertNil(gap.stableTransform)

        var older = readyStability()
        XCTAssertFalse(older.observe(transform(), at: 1.5))
        XCTAssertNil(older.stableTransform)
    }

    func testNonRigidAndNonFiniteInputsCannotBecomeReady() {
        var scaled = transform()
        scaled.columns.0.x = 2
        var invalid = transform()
        invalid.columns.3.x = .nan
        for candidate in [scaled, invalid] {
            var stability = readyStability()
            XCTAssertFalse(stability.observe(candidate, at: 1.8))
            XCTAssertNil(stability.stableTransform)
        }
        var stability = readyStability()
        XCTAssertFalse(stability.observe(transform(), at: .infinity))
        XCTAssertNil(stability.stableTransform)
    }

    private func readyStability() -> ShelfPlacementStability {
        var stability = ShelfPlacementStability()
        for timestamp in [1.0, 1.2, 1.4, 1.6] { stability.observe(transform(), at: timestamp) }
        XCTAssertNotNil(stability.stableTransform)
        return stability
    }

    private func transform(x: Float = 0, degrees: Float = 0) -> simd_float4x4 {
        var result = simd_float4x4(simd_quatf(angle: degrees * .pi / 180, axis: SIMD3(0, 1, 0)))
        result.columns.3 = SIMD4(x, 1, -2, 1)
        return result
    }
}
