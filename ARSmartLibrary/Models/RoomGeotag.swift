import CoreLocation
import Foundation

struct RoomGeotag: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let capturedAt: Date

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double, capturedAt: Date) throws {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.capturedAt = capturedAt
        try validate()
    }

    func validate() throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw RoomGeotagError.invalidCoordinate
        }
        guard horizontalAccuracy.isFinite, (0...100).contains(horizontalAccuracy) else {
            throw RoomGeotagError.invalidAccuracy
        }
        guard capturedAt.timeIntervalSince1970.isFinite else { throw RoomGeotagError.invalidTimestamp }
    }

    static func capture(from location: CLLocation, now: Date = Date()) throws -> RoomGeotag {
        let age = now.timeIntervalSince(location.timestamp)
        guard age.isFinite, (-5...60).contains(age) else { throw RoomGeotagError.staleLocation }
        return try RoomGeotag(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            capturedAt: location.timestamp
        )
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            latitude: values.decode(Double.self, forKey: .latitude),
            longitude: values.decode(Double.self, forKey: .longitude),
            horizontalAccuracy: values.decode(Double.self, forKey: .horizontalAccuracy),
            capturedAt: values.decode(Date.self, forKey: .capturedAt)
        )
    }
}

enum RoomGeotagError: Error, LocalizedError, Equatable {
    case invalidCoordinate
    case invalidAccuracy
    case invalidTimestamp
    case staleLocation

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate: return "The room location has invalid coordinates."
        case .invalidAccuracy: return "The location must be accurate within 100 meters. Try again near a window or entrance."
        case .invalidTimestamp: return "The room location has an invalid capture time."
        case .staleLocation: return "A recent location was unavailable. Try adding the location again."
        }
    }
}
