import CoreLocation
import XCTest
@testable import ARSmartLibrary

final class RoomGeotagTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCaptureAndCodableRoundTripPreserveLocationAccuracyAndTime() throws {
        let tag = try RoomGeotag.capture(from: location(age: 10, accuracy: 12), now: now)
        let restored = try JSONDecoder().decode(RoomGeotag.self, from: JSONEncoder().encode(tag))

        XCTAssertEqual(restored, tag)
        XCTAssertEqual(tag.latitude, 12.9716)
        XCTAssertEqual(tag.longitude, 77.5946)
        XCTAssertEqual(tag.horizontalAccuracy, 12)
        XCTAssertEqual(tag.capturedAt, now.addingTimeInterval(-10))
    }

    func testCaptureRejectsStaleAndTooFarFutureLocations() {
        for age in [60.01, 300, -5.01, -60] {
            XCTAssertThrowsError(try RoomGeotag.capture(from: location(age: age), now: now)) { error in
                XCTAssertEqual(error as? RoomGeotagError, .staleLocation)
            }
        }
        XCTAssertNoThrow(try RoomGeotag.capture(from: location(age: 60), now: now))
        XCTAssertNoThrow(try RoomGeotag.capture(from: location(age: -5), now: now))
    }

    func testCaptureRejectsUnknownAndInsufficientAccuracy() {
        for accuracy in [-1, 100.01, 1_000, Double.infinity, .nan] {
            XCTAssertThrowsError(try RoomGeotag.capture(from: location(accuracy: accuracy), now: now)) { error in
                XCTAssertEqual(error as? RoomGeotagError, .invalidAccuracy)
            }
        }
        XCTAssertNoThrow(try RoomGeotag.capture(from: location(accuracy: 100), now: now))
        XCTAssertNoThrow(try RoomGeotag.capture(from: location(accuracy: 0), now: now))
    }

    func testModelRejectsInvalidCoordinatesAndTimestamp() {
        for latitude in [-90.01, 90.01, Double.infinity, .nan] {
            XCTAssertThrowsError(try RoomGeotag(latitude: latitude, longitude: 0, horizontalAccuracy: 10, capturedAt: now))
        }
        for longitude in [-180.01, 180.01, Double.infinity, .nan] {
            XCTAssertThrowsError(try RoomGeotag(latitude: 0, longitude: longitude, horizontalAccuracy: 10, capturedAt: now))
        }
        XCTAssertThrowsError(try RoomGeotag(latitude: 0, longitude: 0, horizontalAccuracy: 10,
                                           capturedAt: Date(timeIntervalSince1970: .infinity)))
        XCTAssertNoThrow(try RoomGeotag(latitude: -90, longitude: -180, horizontalAccuracy: 10, capturedAt: now))
        XCTAssertNoThrow(try RoomGeotag(latitude: 90, longitude: 180, horizontalAccuracy: 10, capturedAt: now))
    }

    func testStoredGeotagCanBeOldButInvalidStoredCoordinatesAreRejected() throws {
        let oldTag = try RoomGeotag(latitude: 12, longitude: 77, horizontalAccuracy: 20,
                                   capturedAt: now.addingTimeInterval(-86_400))
        let encoded = try JSONEncoder().encode(oldTag)
        XCTAssertEqual(try JSONDecoder().decode(RoomGeotag.self, from: encoded), oldTag)
        var values = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        values["latitude"] = 91
        let invalid = try JSONSerialization.data(withJSONObject: values)

        XCTAssertThrowsError(try JSONDecoder().decode(RoomGeotag.self, from: invalid)) { error in
            XCTAssertEqual(error as? RoomGeotagError, .invalidCoordinate)
        }
    }

    @MainActor
    func testServiceStartsIdleAndCancelWithoutRequestDoesNotPrompt() {
        let service = RoomLocationService()
        service.cancel()

        XCTAssertFalse(service.isRequesting)
        XCTAssertNil(service.latestGeotag)
        XCTAssertEqual(service.message, "Room location is optional.")
    }

    private func location(age: TimeInterval = 0, accuracy: Double = 10) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
                   timestamp: now.addingTimeInterval(-age))
    }
}
