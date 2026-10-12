import Foundation
import simd
import XCTest
@testable import ARSmartLibrary

final class RoomGeotagIntegrationTests: XCTestCase {
    private var directory: URL!
    private var store: LibrarySpaceStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = LibrarySpaceStore(url: directory.appendingPathComponent("library-space.json"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSavedSpacesWithoutGeotagRemainCompatible() throws {
        let spaceID = UUID()
        let worldMap = Data([1, 2, 3])
        let legacy: [String: Any] = [
            "version": 1,
            "space": ["id": spaceID.uuidString, "name": "Existing library", "shelves": [], "bookLocations": []],
            "worldMapData": worldMap.base64EncodedString()
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: legacy).write(to: store.url)

        let saved = try XCTUnwrap(store.load())

        XCTAssertEqual(saved.space.id, spaceID)
        XCTAssertEqual(saved.space.name, "Existing library")
        XCTAssertNil(saved.space.roomGeotag)
        XCTAssertEqual(saved.worldMapData, worldMap)
        XCTAssertNoThrow(try saved.space.validate())
    }

    func testGeotagRoundTripPreservesShelfAssignmentsRoutesAndMap() throws {
        let original = try assignedSpace()
        var tagged = original
        tagged.roomGeotag = try geotag()
        let worldMap = Data([1, 2, 3])
        let entranceImage = Data([4, 5, 6])

        try store.save(space: tagged, worldMapData: worldMap, localizationImageData: entranceImage)
        let saved = try XCTUnwrap(store.load())

        XCTAssertEqual(saved.space, tagged)
        XCTAssertEqual(saved.worldMapData, worldMap)
        XCTAssertEqual(saved.localizationImageData, entranceImage)
        XCTAssertEqual(saved.space.placement(for: "book-one"), original.placement(for: "book-one"))
        XCTAssertEqual(saved.space.shelves, original.shelves)
    }

    func testRemovingGeotagPersistsWithoutChangingShelfData() throws {
        let original = try assignedSpace()
        var tagged = original
        tagged.roomGeotag = try geotag()
        try store.save(space: tagged, worldMapData: Data([1]))
        var reloaded = try XCTUnwrap(store.load()).space

        reloaded.roomGeotag = nil
        try store.save(space: reloaded, worldMapData: Data([2]))

        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.space, original)
        XCTAssertNil(saved.space.roomGeotag)
        XCTAssertEqual(saved.worldMapData, Data([2]))
    }

    @MainActor
    func testAddingAndRemovingGeotagPreservesCatalogAndPendingShelf() throws {
        let book = Book(id: "book-one", title: "One", author: "Author", genre: "Classic", rating: 4, summary: "", keywords: [])
        let controller = LibrarySpaceController(catalog: [book], store: store)
        controller.beginNewSpace(name: "Library")
        controller.beginPlacingShelf(label: "A3", row: "Middle", width: 0.9, height: 0.3, instructions: "By the window")
        let original = try XCTUnwrap(controller.space)
        let tag = try geotag()
        var restartCount = 0
        var workflowChanges = 0
        controller.restartSession = { restartCount += 1 }
        controller.onWorkflowChanged = { workflowChanges += 1 }

        controller.setRoomGeotag(tag, for: original.id)

        XCTAssertEqual(controller.space?.roomGeotag, tag)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertEqual(controller.catalog, [book])
        XCTAssertEqual(controller.pendingShelf?.label, "A3")
        XCTAssertEqual(controller.pendingShelf?.instructions, "By the window")
        XCTAssertEqual(controller.recordedStopCount, 0)
        XCTAssertEqual(restartCount, 0)
        XCTAssertEqual(workflowChanges, 0)

        controller.setRoomGeotag(nil, for: original.id)

        XCTAssertEqual(controller.space, original)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertEqual(controller.pendingShelf?.label, "A3")
        XCTAssertNil(try store.load())
    }

    @MainActor
    func testLateGeotagForReplacedSpaceIsIgnored() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "First room")
        let oldSpaceID = try XCTUnwrap(controller.space?.id)
        controller.beginNewSpace(name: "Replacement room")
        let replacement = controller.space
        let originalMessage = controller.message

        controller.setRoomGeotag(try geotag(), for: oldSpaceID)

        XCTAssertEqual(controller.space, replacement)
        XCTAssertNil(controller.space?.roomGeotag)
        XCTAssertEqual(controller.message, originalMessage)
    }

    @MainActor
    func testGeotagCannotChangeAfterLeavingAdmin() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Library")
        let spaceID = try XCTUnwrap(controller.space?.id)
        controller.setRoomGeotag(try geotag(), for: spaceID)
        controller.setAdminMode(false)
        let original = controller.space

        controller.setRoomGeotag(nil, for: spaceID)

        XCTAssertEqual(controller.space, original)
        XCTAssertFalse(controller.isAdmin)
    }

    private func geotag() throws -> RoomGeotag {
        try RoomGeotag(latitude: 12.9716, longitude: 77.5946, horizontalAccuracy: 12,
                       capturedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func assignedSpace() throws -> LibrarySpace {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(2, 1.2, -4, 1)
        var shelf = LibraryShelf(label: "A3", row: "Middle", worldTransform: transform, width: 0.9, height: 0.3)
        shelf.routeWaypoints = [LibraryWaypoint(worldTransform: matrix_identity_float4x4)]
        var space = LibrarySpace(name: "Library", shelves: [shelf])
        try space.assign(bookID: "book-one", shelfID: shelf.id, slotLabel: "Third from left")
        return space
    }
}
