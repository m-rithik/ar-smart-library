import simd
import XCTest
@testable import ARSmartLibrary

final class ShelfPlacementTests: XCTestCase {
    func testObliqueCameraDoesNotRotateOutlineAwayFromShelfSurface() throws {
        let point = SIMD3<Float>(0, 1.2, -3)
        let transform = try XCTUnwrap(ShelfPlacement.transform(
            at: point, cameraPosition: SIMD3(3, 1.6, 0), surfaceNormal: SIMD3(0, 0, 1)
        ))

        XCTAssertEqual(transform.columns.0, SIMD4(1, 0, 0, 0))
        XCTAssertEqual(transform.columns.1, SIMD4(0, 1, 0, 0))
        XCTAssertEqual(transform.columns.2, SIMD4(0, 0, 1, 0))
        XCTAssertEqual(transform.columns.3, SIMD4(point, 1))
    }

    func testInwardPlaneNormalIsFlippedTowardReader() throws {
        let transform = try XCTUnwrap(ShelfPlacement.transform(
            at: SIMD3(0, 1.2, -3), cameraPosition: SIMD3(1, 1.6, 0), surfaceNormal: SIMD3(0, 0, -1)
        ))

        XCTAssertEqual(transform.columns.2, SIMD4(0, 0, 1, 0))
        XCTAssertEqual(simd_determinant(transform), 1, accuracy: 0.001)
    }

    func testTiltedNormalProducesUprightRigidShelfOutline() throws {
        let transform = try XCTUnwrap(ShelfPlacement.transform(
            at: SIMD3(2, 1.2, -3), cameraPosition: SIMD3(3, 1.6, 0), surfaceNormal: SIMD3(2, 0.1, 2)
        ))
        let expected: Float = 1 / sqrt(2)

        XCTAssertEqual(transform.columns.2.x, expected, accuracy: 0.001)
        XCTAssertEqual(transform.columns.2.y, 0, accuracy: 0.001)
        XCTAssertEqual(transform.columns.2.z, expected, accuracy: 0.001)
        XCTAssertEqual(transform.columns.1, SIMD4(0, 1, 0, 0))
        XCTAssertEqual(simd_determinant(transform), 1, accuracy: 0.001)
    }

    func testDepthOnlyFallbackFacesCamera() throws {
        let transform = try XCTUnwrap(ShelfPlacement.transform(
            at: SIMD3(0, 1.2, 0), cameraPosition: SIMD3(3, 1.6, 0), surfaceNormal: nil
        ))

        XCTAssertEqual(transform.columns.2, SIMD4(1, 0, 0, 0))
        XCTAssertEqual(transform.columns.0, SIMD4(0, 0, -1, 0))
        XCTAssertEqual(simd_determinant(transform), 1, accuracy: 0.001)
    }

    func testInvalidCoordinatesAndUndefinedNormalCannotProduceShelfTransform() {
        XCTAssertNil(ShelfPlacement.transform(at: SIMD3(.nan, 0, 0), cameraPosition: SIMD3(0, 0, 1), surfaceNormal: nil))
        XCTAssertNil(ShelfPlacement.transform(at: .zero, cameraPosition: SIMD3(0, 0, .infinity), surfaceNormal: nil))
        XCTAssertNil(ShelfPlacement.transform(at: .zero, cameraPosition: SIMD3(0.1, 1.6, 0), surfaceNormal: nil))
        XCTAssertNil(ShelfPlacement.transform(at: .zero, cameraPosition: SIMD3(0, 0, 1), surfaceNormal: SIMD3(0, 1, 0)))
        XCTAssertNil(ShelfPlacement.transform(at: .zero, cameraPosition: SIMD3(0, 0, 1), surfaceNormal: SIMD3(.nan, 0, 1)))
    }
}
