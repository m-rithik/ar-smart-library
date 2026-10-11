import XCTest
@testable import ARSmartLibrary

final class ScanTargetTests: XCTestCase {
    func testROIRelativeVisionPointMapsBackToRawImageCoordinates() {
        let region = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)

        let rawPoint = ScanTarget.rawImagePoint(
            fromROIVisionPoint: CGPoint(x: 0.25, y: 0.75),
            regionOfInterest: region
        )

        XCTAssertEqual(rawPoint.x, 0.55, accuracy: 0.001)
        XCTAssertEqual(rawPoint.y, 0.7, accuracy: 0.001)
    }
}
