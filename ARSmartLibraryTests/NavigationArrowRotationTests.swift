import XCTest
@testable import ARSmartLibrary

final class NavigationArrowRotationTests: XCTestCase {
    func testCrossingPositive180ContinuesByTheShortestRotation() {
        XCTAssertEqual(NavigationArrowRotation.angle(from: 179, to: -179), 181)
        XCTAssertEqual(NavigationArrowRotation.angle(from: 170, to: -170), 190)
    }

    func testCrossingNegative180ContinuesByTheShortestRotation() {
        XCTAssertEqual(NavigationArrowRotation.angle(from: -179, to: 179), -181)
        XCTAssertEqual(NavigationArrowRotation.angle(from: -170, to: 170), -190)
    }

    func testPositiveBearingTurnsRightAndNegativeBearingTurnsLeft() {
        XCTAssertEqual(NavigationArrowRotation.angle(from: 0, to: 45), 45)
        XCTAssertEqual(NavigationArrowRotation.angle(from: 0, to: -45), -45)
    }

    func testAccumulatedTurnsStayContinuousInBothDirections() {
        XCTAssertEqual(NavigationArrowRotation.angle(from: 725, to: 10), 730)
        XCTAssertEqual(NavigationArrowRotation.angle(from: -725, to: -10), -730)
        XCTAssertEqual(NavigationArrowRotation.angle(from: 539, to: -179), 541)
        XCTAssertEqual(NavigationArrowRotation.angle(from: -539, to: 179), -541)
    }

    func testEquivalentBearingDoesNotAnimateAnotherFullTurn() {
        XCTAssertEqual(NavigationArrowRotation.angle(from: 720, to: 0), 720)
        XCTAssertEqual(NavigationArrowRotation.angle(from: -720, to: 0), -720)
    }
}
