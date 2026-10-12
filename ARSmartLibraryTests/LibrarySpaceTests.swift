import Foundation
import simd
import XCTest
@testable import ARSmartLibrary

final class LibrarySpaceTests: XCTestCase {
    private var directory: URL!
    private var store: LibrarySpaceStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = LibrarySpaceStore(
            url: directory.appendingPathComponent("library-space.json"),
            catalogBookIDs: ["book-one", "book-two"]
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testCatalogUpdateAllowsCustomAssignmentsToSaveAndReload() throws {
        let custom = try CustomBookStore.makeBook(
            title: "Celestial Orchards", author: "Mira Sen", genre: "Fiction",
            summary: "", keywords: "", rating: 0, existingBooks: []
        )
        let shelf = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [shelf])
        try space.assign(bookID: custom.id, shelfID: shelf.id, slotLabel: "Left")
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))

        store.updateCatalogBookIDs(["book-one", "book-two", custom.id])
        try store.save(space: space, worldMapData: Data([1]))

        XCTAssertEqual(try store.load()?.space.placement(for: custom.id)?.location.slotLabel, "Left")
        try space.assign(bookID: "still-missing", shelfID: shelf.id, slotLabel: "Right")
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))
    }

    func testRoundTripPreservesMapAndActualShelfTransform() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(2.5, 1.2, -4, 1)
        var shelf = makeShelf(transform: transform)
        var aisleTransform = matrix_identity_float4x4
        aisleTransform.columns.3 = SIMD4(0.5, 1.2, -1, 1)
        shelf.routeWaypoints = [LibraryWaypoint(worldTransform: aisleTransform)]
        var space = LibrarySpace(name: "Course library", shelves: [shelf])
        try space.assign(bookID: "book-one", shelfID: shelf.id, slotLabel: "Third book from the left")
        let map = Data([0, 1, 2, 127, 255])

        let localizationImage = Data([1, 2, 3])
        try store.save(space: space, worldMapData: map, localizationImageData: localizationImage)
        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(loaded.space, space)
        XCTAssertEqual(loaded.worldMapData, map)
        XCTAssertEqual(loaded.localizationImageData, localizationImage)
        XCTAssertEqual(loaded.space.shelves[0].position, SIMD3(2.5, 1.2, -4))
        XCTAssertEqual(loaded.space.shelves[0].routeWaypoints[0].position, SIMD3(0.5, 1.2, -1))
    }

    func testAssigningAgainMovesBookAndPreservesOtherAssignments() throws {
        let first = makeShelf()
        let second = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [first, second])
        try space.assign(bookID: "book-one", shelfID: first.id, slotLabel: "Left")
        try space.assign(bookID: "book-two", shelfID: first.id, slotLabel: "Right")
        try space.assign(bookID: "book-one", shelfID: second.id, slotLabel: "  Center  ")

        XCTAssertEqual(space.bookLocations.count, 2)
        XCTAssertEqual(space.placement(for: "book-one")?.shelf.id, second.id)
        XCTAssertEqual(space.placement(for: "book-one")?.location.slotLabel, "Center")
        XCTAssertEqual(space.placement(for: "book-two")?.shelf.id, first.id)
    }

    func testInvalidAssignmentLeavesPreviousLocationUntouched() throws {
        let shelf = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [shelf])
        try space.assign(bookID: "book-one", shelfID: shelf.id, slotLabel: "Left")
        let original = space

        XCTAssertThrowsError(try space.assign(bookID: "book-one", shelfID: UUID(), slotLabel: "Right"))
        XCTAssertEqual(space, original)
        XCTAssertThrowsError(try space.assign(bookID: "book-one", shelfID: shelf.id, slotLabel: " \n "))
        XCTAssertEqual(space, original)
    }

    func testDeletingShelfRemovesOnlyItsBookLocations() throws {
        let first = makeShelf()
        let second = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [first, second])
        try space.assign(bookID: "book-one", shelfID: first.id, slotLabel: "Left")
        try space.assign(bookID: "book-two", shelfID: second.id, slotLabel: "Right")

        space.removeShelf(id: first.id)

        XCTAssertNil(space.placement(for: "book-one"))
        XCTAssertEqual(space.placement(for: "book-two")?.shelf.id, second.id)
        XCTAssertEqual(space.shelves, [second])
    }

    func testRemovingOneBookAssignmentKeepsShelfOtherBooksAndPersists() throws {
        let shelf = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [shelf])
        try space.assign(bookID: "book-one", shelfID: shelf.id, slotLabel: "Left")
        try space.assign(bookID: "book-two", shelfID: shelf.id, slotLabel: "Right")

        space.removeBookAssignment(bookID: "book-one")
        try store.save(space: space, worldMapData: Data([1]))
        let loaded = try XCTUnwrap(store.load()).space

        XCTAssertNil(loaded.placement(for: "book-one"))
        XCTAssertEqual(loaded.placement(for: "book-two")?.location.slotLabel, "Right")
        XCTAssertEqual(loaded.shelves, [shelf])
        XCTAssertEqual(loaded.bookLocations.count, 1)
        let original = space
        space.removeBookAssignment(bookID: "missing-book")
        XCTAssertEqual(space, original)
    }

    func testSavingAfterDeletingFinalShelfKeepsItDeletedOnReload() throws {
        let shelf = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [shelf])
        try space.assign(bookID: "book-one", shelfID: shelf.id, slotLabel: "Left")
        try store.save(space: space, worldMapData: Data([1]))

        space.removeShelf(id: shelf.id)
        let updatedMap = Data([2])
        try store.save(space: space, worldMapData: updatedMap)
        let reloaded = try XCTUnwrap(store.load())

        XCTAssertEqual(reloaded.space.id, space.id)
        XCTAssertTrue(reloaded.space.shelves.isEmpty)
        XCTAssertTrue(reloaded.space.bookLocations.isEmpty)
        XCTAssertNil(reloaded.space.placement(for: "book-one"))
        XCTAssertEqual(reloaded.worldMapData, updatedMap)
    }

    func testSaveRejectsBadDimensionsAndTransformsWithoutReplacingSavedSpace() throws {
        let original = LibrarySpace(name: "Library", shelves: [makeShelf()])
        try store.save(space: original, worldMapData: Data([1]))
        var invalid = original
        for dimension in [Float.zero, -1, .infinity, .nan] {
            invalid.shelves[0].width = dimension
            XCTAssertThrowsError(try store.save(space: invalid, worldMapData: Data([2])))
        }
        invalid = original
        invalid.shelves[0].transform = [0, 1]
        XCTAssertNil(invalid.shelves[0].position)
        XCTAssertThrowsError(try store.save(space: invalid, worldMapData: Data([2])))
        invalid = original
        invalid.shelves[0].transform[12] = .nan
        XCTAssertThrowsError(try store.save(space: invalid, worldMapData: Data([2])))
        invalid = original
        invalid.shelves[0].transform[0] = 0
        XCTAssertThrowsError(try store.save(space: invalid, worldMapData: Data([2])))
        XCTAssertEqual(try store.load()?.space, original)
        XCTAssertEqual(try store.load()?.worldMapData, Data([1]))
    }

    func testSaveRejectsDuplicateAndMissingReferences() throws {
        let shelf = makeShelf()
        var space = LibrarySpace(name: "Library", shelves: [shelf, shelf])
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))

        space.shelves = [shelf]
        let location = BookShelfLocation(bookID: "book-one", shelfID: shelf.id, slotLabel: "Left")
        space.bookLocations = [location, location]
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))

        space.bookLocations = [BookShelfLocation(bookID: "book-one", shelfID: UUID(), slotLabel: "Left")]
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))

        space.bookLocations = [BookShelfLocation(bookID: "unknown-book", shelfID: shelf.id, slotLabel: "Left")]
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))
    }

    func testSaveRejectsInvalidOrDuplicateRouteStops() throws {
        let waypoint = LibraryWaypoint(worldTransform: matrix_identity_float4x4)
        var shelf = makeShelf()
        shelf.routeWaypoints = [waypoint, waypoint]
        var space = LibrarySpace(name: "Library", shelves: [shelf])
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1]))) { error in
            XCTAssertEqual(error as? LibrarySpaceError, .duplicateWaypoint)
        }

        var secondShelf = makeShelf()
        shelf.routeWaypoints = [waypoint]
        secondShelf.routeWaypoints = [waypoint]
        space.shelves = [shelf, secondShelf]
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1]))) { error in
            XCTAssertEqual(error as? LibrarySpaceError, .duplicateWaypoint)
        }

        space.shelves = [shelf]
        space.shelves[0].routeWaypoints = [LibraryWaypoint(transform: [0, 1])]
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1]))) { error in
            XCTAssertEqual(error as? LibrarySpaceError, .invalidWaypointTransform)
        }

        var invalidWaypoint = waypoint
        invalidWaypoint.transform[14] = .infinity
        space.shelves[0].routeWaypoints = [invalidWaypoint]
        XCTAssertThrowsError(try store.save(space: space, worldMapData: Data([1])))
    }

    func testLoadRejectsCorruptMetadataAndMissingMap() throws {
        let shelf = makeShelf()
        let space = LibrarySpace(name: "Library", shelves: [shelf])
        try store.save(space: space, worldMapData: Data([1]))
        try Data("not JSON".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())

        var corrupt = space
        corrupt.bookLocations = [BookShelfLocation(bookID: "book-one", shelfID: UUID(), slotLabel: "Left")]
        try JSONEncoder().encode(SavedLibrarySpace(space: corrupt, worldMapData: Data([1]))).write(to: store.url)
        XCTAssertThrowsError(try store.load())

        try JSONEncoder().encode(SavedLibrarySpace(space: space, worldMapData: Data())).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }

    func testLoadRejectsUnsupportedVersion() throws {
        let space = LibrarySpace(name: "Library", shelves: [makeShelf()])
        try store.save(space: space, worldMapData: Data([1]))
        let data = try Data(contentsOf: store.url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: store.url)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? LibrarySpaceError, .unsupportedVersion)
        }
    }

    func testClearOnlyRemovesTheSpaceFile() throws {
        XCTAssertNil(try store.load())
        try store.clear()
        try store.save(space: LibrarySpace(name: "Library"), worldMapData: Data([1]))
        let sibling = directory.appendingPathComponent("other-data.txt")
        try Data([3]).write(to: sibling)

        try store.clear()

        XCTAssertNil(try store.load())
        XCTAssertEqual(try Data(contentsOf: sibling), Data([3]))
    }

    func testClearRejectsDirectoryInsteadOfDeletingItsContents() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sibling = directory.appendingPathComponent("other-data.txt")
        try Data([3]).write(to: sibling)
        let invalidStore = LibrarySpaceStore(url: directory)

        XCTAssertThrowsError(try invalidStore.clear())
        XCTAssertEqual(try Data(contentsOf: sibling), Data([3]))
    }

    private func makeShelf(transform: simd_float4x4 = matrix_identity_float4x4) -> LibraryShelf {
        LibraryShelf(label: "Shelf A", row: "Row 2", worldTransform: transform, width: 0.9, height: 0.3)
    }
}
