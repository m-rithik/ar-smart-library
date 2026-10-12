import ARKit
import XCTest
@testable import ARSmartLibrary

final class RoomScanGuidanceTests: XCTestCase {
    func testTrackingProblemsTakePriorityOverMappedArea() {
        XCTAssertEqual(guidance(tracking: .notAvailable).status, .unavailable)
        XCTAssertEqual(guidance(tracking: .limited(.initializing)).status, .initializing)
        XCTAssertEqual(guidance(tracking: .limited(.excessiveMotion)).status, .excessiveMotion)
        XCTAssertEqual(guidance(tracking: .limited(.insufficientFeatures)).status, .insufficientFeatures)
    }

    func testInstructionsDistinguishMovingTooFastFromInsufficientDetail() {
        let motion = guidance(tracking: .limited(.excessiveMotion))
        let features = guidance(tracking: .limited(.insufficientFeatures))

        XCTAssertTrue(motion.instruction.contains("Pause walking"))
        XCTAssertTrue(features.instruction.contains("book spines"))
        XCTAssertTrue(features.instruction.contains("blank walls"))
    }

    func testNewRoomDoesNotAskForSavedEntrancePhoto() {
        let starting = guidance(tracking: .limited(.initializing), isNew: true)
        let interrupted = guidance(tracking: .limited(.relocalizing), isNew: true, timedOut: true)
        let origin = guidance(origin: false, isNew: true, timedOut: true)

        XCTAssertFalse(starting.instruction.contains("saved"))
        XCTAssertFalse(interrupted.instruction.contains("saved"))
        XCTAssertEqual(origin.status, .locatingOrigin)
        XCTAssertFalse(origin.instruction.contains("saved"))
    }

    func testRestoredRoomRequiresOriginEvenWhenTrackingAndMappingAreReady() {
        let result = guidance(origin: false, isNew: false)

        XCTAssertEqual(result.status, .relocalizing)
        XCTAssertTrue(result.instruction.contains("saved entrance"))
    }

    func testLongRelocalizationWaitGivesSpecificReferenceViewInstructions() {
        let result = guidance(tracking: .limited(.relocalizing), isNew: false, timedOut: true)

        XCTAssertEqual(result.status, .relocalizationDelayed)
        XCTAssertTrue(result.instruction.contains("phone height and direction"))
        XCTAssertTrue(result.instruction.contains("entrance photo if one is shown"))
    }

    func testMissingShelfAnchorsTakePriorityOverMappedStatus() {
        let result = guidance(anchors: false)

        XCTAssertEqual(result.status, .restoringAnchors)
        XCTAssertTrue(result.instruction.contains("shelf rows and aisle turns"))
    }

    func testMappingUnavailableAndLimitedRequestMoreSurfaceDetail() {
        XCTAssertEqual(guidance(mapping: .notAvailable).status, .mappingUnavailable)
        XCTAssertEqual(guidance(mapping: .limited).status, .mappingLimited)
        XCTAssertTrue(guidance(mapping: .limited).instruction.contains("another angle"))
    }

    func testExtendingIsAlreadySuitableForSaving() {
        let result = guidance(mapping: .extending, shelves: 2)

        XCTAssertEqual(result.status, .mappingExtending)
        XCTAssertTrue(result.instruction.contains("enough detail to save"))
        XCTAssertTrue(result.instruction.contains("finishing your shelf work"))
    }

    func testMappedStatusDescribesVisibleAreaAndMovesToShelfSetup() {
        let empty = guidance(shelves: 0)
        let placed = guidance(shelves: 2)

        XCTAssertEqual(empty.status, .visibleAreaMapped)
        XCTAssertEqual(empty.title, "Visible area mapped")
        XCTAssertTrue(empty.instruction.contains("Add a shelf row"))
        XCTAssertTrue(placed.instruction.contains("save the AR space"))
        XCTAssertFalse(placed.title.contains("Room mapped"))
    }

    func testOldRelocalizationTimeoutDoesNotOverrideRecoveredState() {
        XCTAssertEqual(guidance(isNew: false, timedOut: true).status, .visibleAreaMapped)
    }

    private func guidance(
        tracking: ARCamera.TrackingState = .normal,
        mapping: ARFrame.WorldMappingStatus = .mapped,
        origin: Bool = true,
        anchors: Bool = true,
        isNew: Bool = true,
        shelves: Int = 1,
        timedOut: Bool = false
    ) -> RoomScanGuidance {
        RoomScanGuidance.evaluate(
            trackingState: tracking, mappingStatus: mapping,
            originRecognized: origin, allAnchorsAvailable: anchors,
            isNewSpace: isNew, shelfCount: shelves,
            relocalizationTimedOut: timedOut
        )
    }
}
