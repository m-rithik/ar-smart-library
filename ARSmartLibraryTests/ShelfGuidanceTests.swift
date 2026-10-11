import XCTest
import simd
@testable import ARSmartLibrary

final class ShelfGuidanceTests: XCTestCase {
    func testReadyCameraFacingNegativeZReportsShelfAhead() throws {
        let guidance = try XCTUnwrap(guidance(to: SIMD3(0, 0, -3)))

        XCTAssertEqual(guidance.bearing, .ahead)
        XCTAssertEqual(guidance.bearingDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(guidance.distance, 3, accuracy: 0.001)
        XCTAssertEqual(guidance.horizontalDistance, 3, accuracy: 0.001)
        XCTAssertFalse(guidance.arrived)
        XCTAssertEqual(guidance.instruction, "Shelf is 3.0 m ahead.")
    }

    func testLeftRightAndBehindBearings() throws {
        let left = try XCTUnwrap(guidance(to: SIMD3(-2, 0, 0)))
        let right = try XCTUnwrap(guidance(to: SIMD3(2, 0, 0)))
        let behind = try XCTUnwrap(guidance(to: SIMD3(0, 0, 2)))

        XCTAssertEqual(left.bearing, .left)
        XCTAssertEqual(left.bearingDegrees, -90, accuracy: 0.001)
        XCTAssertEqual(right.bearing, .right)
        XCTAssertEqual(right.bearingDegrees, 90, accuracy: 0.001)
        XCTAssertEqual(behind.bearing, .behind)
        XCTAssertEqual(abs(behind.bearingDegrees), 180, accuracy: 0.001)
        XCTAssertEqual(right.instruction, "Turn right 90°. Shelf is 2.0 m away.")
    }

    func testCameraYawAndTranslationChangeBearing() throws {
        var camera = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0)))
        camera.columns.3 = SIMD4(4, 1.5, 7, 1)

        let ahead = try XCTUnwrap(guidance(to: SIMD3(7, 1.5, 7), camera: camera))
        let right = try XCTUnwrap(guidance(to: SIMD3(4, 1.5, 10), camera: camera))

        XCTAssertEqual(ahead.bearing, .ahead)
        XCTAssertEqual(ahead.bearingDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(ahead.horizontalDistance, 3, accuracy: 0.001)
        XCTAssertEqual(right.bearing, .right)
        XCTAssertEqual(right.bearingDegrees, 90, accuracy: 0.001)
    }

    func testCameraPitchDoesNotChangeHorizontalDirection() throws {
        let yaw = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0))
        let camera = simd_float4x4(yaw * pitch)
        let guidance = try XCTUnwrap(guidance(to: SIMD3(3, 0, 0), camera: camera))

        XCTAssertEqual(guidance.bearing, .ahead)
        XCTAssertEqual(guidance.bearingDegrees, 0, accuracy: 0.001)
    }

    func testArrivalUsesHorizontalDistanceAndPreservesShelfHeight() throws {
        var camera = matrix_identity_float4x4
        camera.columns.3.y = 1.6
        let below = try XCTUnwrap(guidance(to: SIMD3(0, 0.5, -0.8), camera: camera))
        let above = try XCTUnwrap(guidance(to: SIMD3(0, 2.4, -0.5), camera: camera))
        let outside = try XCTUnwrap(guidance(to: SIMD3(0, 1.6, -0.81), camera: camera))

        XCTAssertTrue(below.arrived)
        XCTAssertGreaterThan(below.distance, 0.8)
        XCTAssertEqual(below.heightDifference, -1.1, accuracy: 0.001)
        XCTAssertEqual(below.verticalHint, .below)
        XCTAssertEqual(below.instruction, "At the shelf. Look 1.1 m below the phone.")
        XCTAssertEqual(above.verticalHint, .above)
        XCTAssertFalse(outside.arrived)
        XCTAssertEqual(outside.verticalHint, .level)
    }

    func testCoincidentTargetHasFiniteGuidance() throws {
        let guidance = try XCTUnwrap(guidance(to: .zero))

        XCTAssertTrue(guidance.arrived)
        XCTAssertEqual(guidance.distance, 0)
        XCTAssertEqual(guidance.bearingDegrees, 0)
        XCTAssertEqual(guidance.verticalHint, .level)
    }

    func testDoesNotGuideUntilTrackingAndLocalizationAreReady() {
        XCTAssertNil(ShelfGuidance.calculate(
            cameraTransform: matrix_identity_float4x4,
            targetPosition: SIMD3(0, 0, -3),
            isReady: false
        ))
    }

    func testRejectsNonFiniteCoordinatesAndUndefinedHeading() {
        XCTAssertNil(guidance(to: SIMD3(.nan, 0, -3)))
        XCTAssertNil(guidance(to: SIMD3(0, .infinity, -3)))

        var invalidCamera = matrix_identity_float4x4
        invalidCamera.columns.3.x = .nan
        XCTAssertNil(guidance(to: SIMD3(0, 0, -3), camera: invalidCamera))

        let verticalCamera = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)))
        XCTAssertNil(guidance(to: SIMD3(0, 0, -3), camera: verticalCamera))

        XCTAssertNil(guidance(to: SIMD3(.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude)))
    }

    func testRouteRequiresCommonEntryAndFollowsCheckpointsInOrder() {
        let entry = SIMD3<Float>(0, 0, 0)
        let corner = SIMD3<Float>(0, 0, -3)
        let shelf = SIMD3<Float>(3, 1.4, -3)
        var route = ShelfRouteProgress(waypointPositions: [entry, corner], shelfPosition: shelf)

        route.update(cameraPosition: shelf, isReady: true)
        XCTAssertEqual(route.waypointIndex, 0)
        XCTAssertEqual(route.activeTargetPosition, entry)
        XCTAssertFalse(route.isAtShelf)

        route.update(cameraPosition: SIMD3(0.66, 1.6, 0), isReady: true)
        XCTAssertEqual(route.waypointIndex, 0)
        route.update(cameraPosition: SIMD3(0.65, 1.6, 0), isReady: true)
        XCTAssertEqual(route.waypointIndex, 1)
        XCTAssertEqual(route.activeTargetPosition, corner)

        route.update(cameraPosition: shelf, isReady: true)
        XCTAssertEqual(route.waypointIndex, 1)
        XCTAssertFalse(route.isAtShelf)

        route.update(cameraPosition: SIMD3(0, 1.6, -3), isReady: true)
        XCTAssertFalse(route.isFollowingWaypoints)
        XCTAssertEqual(route.activeTargetPosition, shelf)
        XCTAssertFalse(route.isAtShelf)

        route.update(cameraPosition: SIMD3(3, 1.6, -3.8), isReady: true)
        XCTAssertTrue(route.isAtShelf)
        route.update(cameraPosition: SIMD3(3, 1.6, -4), isReady: true)
        XCTAssertFalse(route.isAtShelf)
    }

    func testRouteAdvancesAtMostOneColocatedCheckpointPerUpdate() {
        var route = ShelfRouteProgress(waypointPositions: [.zero, .zero], shelfPosition: .zero)

        route.update(cameraPosition: .zero, isReady: true)
        XCTAssertEqual(route.waypointIndex, 1)
        XCTAssertFalse(route.isAtShelf)

        route.update(cameraPosition: .zero, isReady: true)
        XCTAssertEqual(route.waypointIndex, 2)
        XCTAssertFalse(route.isAtShelf)

        route.update(cameraPosition: .zero, isReady: true)
        XCTAssertTrue(route.isAtShelf)

        route.reset()
        XCTAssertEqual(route.waypointIndex, 0)
        XCTAssertTrue(route.isFollowingWaypoints)
        XCTAssertFalse(route.isAtShelf)
    }

    func testRouteCannotAdvanceWithSuspendedTrackingOrInvalidCoordinates() {
        var route = ShelfRouteProgress(waypointPositions: [.zero], shelfPosition: SIMD3(0, 0, -2))

        route.update(cameraPosition: .zero, isReady: false)
        route.update(cameraPosition: SIMD3(0, .nan, 0), isReady: true)
        XCTAssertEqual(route.waypointIndex, 0)
        XCTAssertFalse(route.isAtShelf)

        var invalidRoute = ShelfRouteProgress(
            waypointPositions: [.zero, SIMD3(.infinity, 0, 0)],
            shelfPosition: SIMD3(0, 0, -2)
        )
        invalidRoute.update(cameraPosition: .zero, isReady: true)
        XCTAssertEqual(invalidRoute.waypointIndex, 0)
    }

    func testRouteWithoutCheckpointsTargetsShelfAndResetClearsArrival() {
        let shelf = SIMD3<Float>(2, 0.5, -1)
        var route = ShelfRouteProgress(waypointPositions: [], shelfPosition: shelf)

        XCTAssertEqual(route.activeTargetPosition, shelf)
        XCTAssertFalse(route.isFollowingWaypoints)
        route.update(cameraPosition: shelf, isReady: false)
        XCTAssertFalse(route.isAtShelf)
        route.update(cameraPosition: shelf, isReady: true)
        XCTAssertTrue(route.isAtShelf)
        route.reset()
        XCTAssertFalse(route.isAtShelf)
    }

    func testRefreshedAnchorsPreserveCheckpointProgressAndChangeArrivalCoordinates() {
        var route = ShelfRouteProgress(
            waypointPositions: [.zero, SIMD3(0, 0, -2)],
            shelfPosition: SIMD3(3, 1.5, -2)
        )
        route.update(cameraPosition: .zero, isReady: true)

        XCTAssertTrue(route.refreshPositions(
            waypointPositions: [SIMD3(5, 0, 0), SIMD3(5, 0, -2)],
            shelfPosition: SIMD3(8, 1.5, -2)
        ))
        XCTAssertEqual(route.waypointIndex, 1)
        XCTAssertEqual(route.activeTargetPosition, SIMD3(5, 0, -2))

        route.update(cameraPosition: SIMD3(0, 1.6, -2), isReady: true)
        XCTAssertEqual(route.waypointIndex, 1)
        route.update(cameraPosition: SIMD3(5, 1.6, -2), isReady: true)
        XCTAssertEqual(route.waypointIndex, 2)
        XCTAssertEqual(route.activeTargetPosition, SIMD3(8, 1.5, -2))

        route.update(cameraPosition: SIMD3(3, 1.6, -2), isReady: true)
        XCTAssertFalse(route.isAtShelf)
        route.update(cameraPosition: SIMD3(8, 1.6, -2), isReady: true)
        XCTAssertTrue(route.isAtShelf)

        XCTAssertTrue(route.refreshPositions(
            waypointPositions: [SIMD3(5, 0, 0), SIMD3(5, 0, -2)],
            shelfPosition: SIMD3(9, 1.5, -2)
        ))
        XCTAssertFalse(route.isAtShelf)
        XCTAssertEqual(route.waypointIndex, 2)
        route.update(cameraPosition: SIMD3(8, 1.6, -2), isReady: true)
        XCTAssertFalse(route.isAtShelf)
        route.update(cameraPosition: SIMD3(9, 1.6, -2), isReady: true)
        XCTAssertTrue(route.isAtShelf)
    }

    func testRefreshRejectsChangedTopologyOrInvalidAnchorsWithoutPartialUpdates() {
        let waypoints = [SIMD3<Float>.zero, SIMD3(0, 0, -2)]
        let shelf = SIMD3<Float>(3, 1.5, -2)
        var route = ShelfRouteProgress(waypointPositions: waypoints, shelfPosition: shelf)
        route.update(cameraPosition: .zero, isReady: true)

        XCTAssertFalse(route.refreshPositions(waypointPositions: [.zero], shelfPosition: SIMD3(4, 0, 0)))
        XCTAssertFalse(route.refreshPositions(
            waypointPositions: [.zero, SIMD3(.nan, 0, 0)],
            shelfPosition: SIMD3(4, 0, 0)
        ))
        XCTAssertFalse(route.refreshPositions(waypointPositions: waypoints, shelfPosition: SIMD3(4, .infinity, 0)))
        XCTAssertEqual(route.waypointPositions, waypoints)
        XCTAssertEqual(route.shelfPosition, shelf)
        XCTAssertEqual(route.waypointIndex, 1)
    }

    func testArrivalClearsWhenTrackingOrCameraPositionCannotBeEvaluated() {
        var route = ShelfRouteProgress(waypointPositions: [.zero], shelfPosition: .zero)
        route.update(cameraPosition: .zero, isReady: true)
        route.update(cameraPosition: .zero, isReady: true)
        XCTAssertTrue(route.isAtShelf)

        route.update(cameraPosition: .zero, isReady: false)
        XCTAssertFalse(route.isAtShelf)
        XCTAssertEqual(route.waypointIndex, 1)
        route.update(cameraPosition: .zero, isReady: true)
        XCTAssertTrue(route.isAtShelf)

        route.update(cameraPosition: SIMD3(.nan, 0, 0), isReady: true)
        XCTAssertFalse(route.isAtShelf)
        XCTAssertEqual(route.waypointIndex, 1)
    }

    private func guidance(
        to position: SIMD3<Float>,
        camera: simd_float4x4 = matrix_identity_float4x4
    ) -> ShelfGuidance? {
        ShelfGuidance.calculate(cameraTransform: camera, targetPosition: position, isReady: true)
    }
}
