import Foundation
import simd

struct LibraryShelf: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var row: String
    var instructions: String
    var transform: [Float]
    var width: Float
    var height: Float
    var routeWaypoints: [LibraryWaypoint]

    init(
        id: UUID = UUID(),
        label: String,
        row: String,
        instructions: String = "",
        transform: [Float],
        width: Float,
        height: Float,
        routeWaypoints: [LibraryWaypoint] = []
    ) {
        self.id = id
        self.label = label
        self.row = row
        self.instructions = instructions
        self.transform = transform
        self.width = width
        self.height = height
        self.routeWaypoints = routeWaypoints
    }

    init(
        id: UUID = UUID(),
        label: String,
        row: String,
        instructions: String = "",
        worldTransform: simd_float4x4,
        width: Float,
        height: Float,
        routeWaypoints: [LibraryWaypoint] = []
    ) {
        self.init(
            id: id,
            label: label,
            row: row,
            instructions: instructions,
            transform: LibraryWorldTransform.encode(worldTransform),
            width: width,
            height: height,
            routeWaypoints: routeWaypoints
        )
    }

    var worldTransform: simd_float4x4? {
        LibraryWorldTransform.decode(transform)
    }

    var position: SIMD3<Float>? {
        guard let transform = worldTransform else { return nil }
        return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}

struct LibraryWaypoint: Codable, Equatable, Identifiable {
    var id: UUID
    var transform: [Float]

    init(id: UUID = UUID(), transform: [Float]) {
        self.id = id
        self.transform = transform
    }

    init(id: UUID = UUID(), worldTransform: simd_float4x4) {
        self.init(id: id, transform: LibraryWorldTransform.encode(worldTransform))
    }

    var worldTransform: simd_float4x4? {
        LibraryWorldTransform.decode(transform)
    }

    var position: SIMD3<Float>? {
        guard let transform = worldTransform else { return nil }
        return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}

private enum LibraryWorldTransform {
    static func encode(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in
            (0..<4).map { matrix[column][$0] }
        }
    }

    static func decode(_ transform: [Float]) -> simd_float4x4? {
        guard transform.count == 16, transform.allSatisfy(\.isFinite) else { return nil }
        let matrix = simd_float4x4(columns: (
            SIMD4(transform[0], transform[1], transform[2], transform[3]),
            SIMD4(transform[4], transform[5], transform[6], transform[7]),
            SIMD4(transform[8], transform[9], transform[10], transform[11]),
            SIMD4(transform[12], transform[13], transform[14], transform[15])
        ))
        // AR world anchors use rigid, affine transforms. Reject corrupt or scaled frames.
        let x = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let y = SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let z = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let tolerance: Float = 0.01
        guard abs(matrix.columns.0.w) < tolerance,
              abs(matrix.columns.1.w) < tolerance,
              abs(matrix.columns.2.w) < tolerance,
              abs(matrix.columns.3.w - 1) < tolerance,
              abs(simd_length(x) - 1) < tolerance,
              abs(simd_length(y) - 1) < tolerance,
              abs(simd_length(z) - 1) < tolerance,
              abs(simd_dot(x, y)) < tolerance,
              abs(simd_dot(x, z)) < tolerance,
              abs(simd_dot(y, z)) < tolerance,
              simd_dot(simd_cross(x, y), z) > 1 - tolerance else { return nil }
        return matrix
    }

}

struct BookShelfLocation: Codable, Equatable {
    var bookID: String
    var shelfID: UUID
    var slotLabel: String
}

struct LibraryBookPlacement: Equatable {
    let location: BookShelfLocation
    let shelf: LibraryShelf
}

struct LibrarySpace: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var shelves: [LibraryShelf]
    var bookLocations: [BookShelfLocation]

    init(
        id: UUID = UUID(),
        name: String,
        shelves: [LibraryShelf] = [],
        bookLocations: [BookShelfLocation] = []
    ) {
        self.id = id
        self.name = name
        self.shelves = shelves
        self.bookLocations = bookLocations
    }

    func validate(catalogBookIDs: Set<String>? = nil) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibrarySpaceError.missingSpaceName
        }
        var shelfIDs = Set<UUID>()
        var waypointIDs = Set<UUID>()
        for shelf in shelves {
            guard shelfIDs.insert(shelf.id).inserted else { throw LibrarySpaceError.duplicateShelf }
            guard !shelf.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shelf.row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibrarySpaceError.missingShelfLabel
            }
            guard shelf.width.isFinite, shelf.height.isFinite,
                  shelf.width > 0, shelf.height > 0 else {
                throw LibrarySpaceError.invalidShelfDimensions
            }
            guard shelf.worldTransform != nil else { throw LibrarySpaceError.invalidShelfTransform }
            for waypoint in shelf.routeWaypoints {
                guard waypointIDs.insert(waypoint.id).inserted else { throw LibrarySpaceError.duplicateWaypoint }
                guard waypoint.worldTransform != nil else { throw LibrarySpaceError.invalidWaypointTransform }
            }
        }
        var bookIDs = Set<String>()
        for location in bookLocations {
            guard !location.bookID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibrarySpaceError.missingBook
            }
            guard bookIDs.insert(location.bookID).inserted else { throw LibrarySpaceError.duplicateBookLocation }
            guard shelfIDs.contains(location.shelfID) else { throw LibrarySpaceError.missingShelf }
            guard !location.slotLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibrarySpaceError.missingSlotLabel
            }
            if let catalogBookIDs, !catalogBookIDs.contains(location.bookID) {
                throw LibrarySpaceError.missingBook
            }
        }
    }

    mutating func assign(bookID: String, shelfID: UUID, slotLabel: String) throws {
        var updated = self
        updated.bookLocations.removeAll { $0.bookID == bookID }
        updated.bookLocations.append(BookShelfLocation(
            bookID: bookID,
            shelfID: shelfID,
            slotLabel: slotLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        try updated.validate()
        self = updated
    }

    mutating func removeShelf(id: UUID) {
        shelves.removeAll { $0.id == id }
        bookLocations.removeAll { $0.shelfID == id }
    }

    mutating func removeBookAssignment(bookID: String) {
        bookLocations.removeAll { $0.bookID == bookID }
    }

    func placement(for bookID: String) -> LibraryBookPlacement? {
        guard let location = bookLocations.first(where: { $0.bookID == bookID }),
              let shelf = shelves.first(where: { $0.id == location.shelfID }) else { return nil }
        return LibraryBookPlacement(location: location, shelf: shelf)
    }
}

enum LibrarySpaceError: Error, LocalizedError, Equatable {
    case missingSpaceName
    case duplicateShelf
    case missingShelfLabel
    case invalidShelfDimensions
    case invalidShelfTransform
    case duplicateWaypoint
    case invalidWaypointTransform
    case duplicateBookLocation
    case missingShelf
    case missingBook
    case missingSlotLabel
    case missingWorldMap
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .missingSpaceName:
            return "Give the library space a name."
        case .duplicateShelf:
            return "The library space contains duplicate shelf identifiers."
        case .missingShelfLabel:
            return "Each shelf needs a label and row."
        case .invalidShelfDimensions:
            return "Shelf width and height must be positive, finite measurements."
        case .invalidShelfTransform:
            return "A shelf has an invalid AR position. Place it again before saving."
        case .duplicateWaypoint:
            return "The library space contains duplicate aisle stop identifiers."
        case .invalidWaypointTransform:
            return "An aisle stop has an invalid AR position. Record the route again before saving."
        case .duplicateBookLocation:
            return "A book has more than one saved shelf location."
        case .missingShelf:
            return "A book refers to a shelf that does not exist."
        case .missingBook:
            return "A shelf assignment refers to a book that is missing from the catalog."
        case .missingSlotLabel:
            return "Describe the book's position on the shelf."
        case .missingWorldMap:
            return "The library space needs a saved AR map. Scan the room and save again."
        case .unsupportedVersion:
            return "This library space was saved in an unsupported format."
        }
    }
}
