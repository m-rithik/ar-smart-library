import Foundation
import XCTest
@testable import ARSmartLibrary

final class LibrarySpaceControllerTests: XCTestCase {
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

    @MainActor
    func testNewSpaceStartsUnsavedAdminWorkflowAndRequestsSessionRestart() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        var restartCount = 0
        controller.restartSession = { restartCount += 1 }

        controller.beginNewSpace(name: "  Course library  ")

        XCTAssertEqual(controller.space?.name, "Course library")
        XCTAssertEqual(controller.space?.shelves.count, 0)
        XCTAssertTrue(controller.isAdmin)
        XCTAssertTrue(controller.isBusyWithSpace)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertFalse(controller.hasSavedSpace)
        XCTAssertFalse(controller.isLocalized)
        XCTAssertFalse(controller.canSave)
        XCTAssertEqual(restartCount, 1)
        XCTAssertNil(try store.load())
    }

    @MainActor
    func testSuspendingGuidancePreservesWorkingSpaceAndShelfDraft() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Library")
        beginShelfDraft(on: controller)
        let originalSpace = controller.space
        let originalDraft = try XCTUnwrap(controller.pendingShelf)

        controller.suspendGuidance()

        XCTAssertEqual(controller.space, originalSpace)
        let retainedDraft = try XCTUnwrap(controller.pendingShelf)
        XCTAssertEqual(retainedDraft.label, originalDraft.label)
        XCTAssertEqual(retainedDraft.row, originalDraft.row)
        XCTAssertEqual(retainedDraft.width, originalDraft.width)
        XCTAssertEqual(retainedDraft.height, originalDraft.height)
        XCTAssertEqual(retainedDraft.instructions, originalDraft.instructions)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertFalse(controller.isLocalized)
        XCTAssertFalse(controller.canSave)
        XCTAssertNil(controller.guidance)
        XCTAssertNil(controller.shelfScreenPosition)
    }

    @MainActor
    func testLeavingAdminRequiresExplicitCancellationOfShelfDraft() {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Library")
        beginShelfDraft(on: controller)
        let originalSpace = controller.space

        controller.setAdminMode(false)

        XCTAssertTrue(controller.isAdmin)
        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertEqual(controller.space, originalSpace)
        XCTAssertTrue(controller.hasWorkingChanges)

        controller.cancelShelfPlacement()
        controller.setAdminMode(false)

        XCTAssertFalse(controller.isAdmin)
        XCTAssertFalse(controller.isBusyWithSpace)
        XCTAssertNil(controller.pendingShelf)
        XCTAssertEqual(controller.recordedStopCount, 0)
        XCTAssertEqual(controller.space, originalSpace)
        XCTAssertTrue(controller.hasUnsavedChanges)
    }

    @MainActor
    func testRedundantAdminSelectionAndNewPlacementCannotReplaceDraft() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Library")
        beginShelfDraft(on: controller)
        let originalDraft = try XCTUnwrap(controller.pendingShelf)
        var workflowChanges = 0
        controller.onWorkflowChanged = { workflowChanges += 1 }

        controller.setAdminMode(true)
        controller.beginPlacingShelf(label: "Other", row: "Bottom", width: 1, height: 0.4, instructions: "")

        XCTAssertEqual(controller.pendingShelf?.label, originalDraft.label)
        XCTAssertEqual(controller.pendingShelf?.row, originalDraft.row)
        XCTAssertTrue(controller.isAdmin)
        XCTAssertEqual(workflowChanges, 0)
    }

    @MainActor
    func testStartingDirectionsCannotDiscardShelfDraft() throws {
        let book = Book(id: "one", title: "One", author: "Author", genre: "Classic", rating: 4, summary: "", keywords: [])
        let controller = LibrarySpaceController(catalog: [book], store: store)
        controller.beginNewSpace(name: "Library")
        beginShelfDraft(on: controller)

        controller.navigate(to: book)

        XCTAssertTrue(controller.isAdmin)
        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertNil(controller.targetBook)
        XCTAssertTrue(controller.message.contains("current shelf placement"))
    }

    @MainActor
    func testMissingSavedSpacePreservesCurrentWorkAndDoesNotRestart() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Working library")
        beginShelfDraft(on: controller)
        let originalSpace = controller.space
        var restartCount = 0
        controller.restartSession = { restartCount += 1 }

        XCTAssertFalse(controller.restoreSavedSpace())

        XCTAssertEqual(controller.space, originalSpace)
        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertTrue(controller.isAdmin)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertFalse(controller.hasSavedSpace)
        XCTAssertEqual(restartCount, 0)
    }

    @MainActor
    func testCorruptSavedDataPreservesCurrentWorkAndDoesNotRestart() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Working library")
        beginShelfDraft(on: controller)
        let originalSpace = controller.space
        var restartCount = 0
        controller.restartSession = { restartCount += 1 }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptData = Data("not a saved space".utf8)
        try corruptData.write(to: store.url)

        XCTAssertFalse(controller.restoreSavedSpace())

        XCTAssertEqual(controller.space, originalSpace)
        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertTrue(controller.isAdmin)
        XCTAssertEqual(restartCount, 0)
        XCTAssertEqual(try Data(contentsOf: store.url), corruptData)
    }

    @MainActor
    func testUnreadableWorldMapPreservesCurrentWorkAndDoesNotRestart() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Working library")
        beginShelfDraft(on: controller)
        let originalSpace = controller.space
        var restartCount = 0
        controller.restartSession = { restartCount += 1 }
        // A securely encoded object of the wrong type must not be accepted as an AR map.
        let invalidMap = try NSKeyedArchiver.archivedData(withRootObject: "not a map" as NSString, requiringSecureCoding: true)
        try store.save(space: LibrarySpace(name: "Saved library"), worldMapData: invalidMap)

        XCTAssertFalse(controller.restoreSavedSpace())

        XCTAssertEqual(controller.space, originalSpace)
        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertEqual(restartCount, 0)
    }

    @MainActor
    func testFatalResetClearsUnrecoverableCoordinatesAndRestartsWhenNoSaveExists() {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Working library")
        beginShelfDraft(on: controller)
        var restartCount = 0
        controller.restartSession = { restartCount += 1 }

        controller.recoverAfterSessionFailure()

        XCTAssertNil(controller.space)
        XCTAssertNil(controller.pendingShelf)
        XCTAssertFalse(controller.hasWorkingChanges)
        XCTAssertFalse(controller.hasSavedSpace)
        XCTAssertFalse(controller.isLocalized)
        XCTAssertFalse(controller.canSave)
        XCTAssertEqual(restartCount, 1)
        XCTAssertTrue(controller.message.contains("could not be recovered"))
    }

    @MainActor
    func testFatalResetClearsUnrecoverableCoordinatesWhenSavedDataIsCorrupt() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Working library")
        beginShelfDraft(on: controller)
        var restartCount = 0
        controller.restartSession = { restartCount += 1 }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptData = Data("not a saved space".utf8)
        try corruptData.write(to: store.url)

        controller.recoverAfterSessionFailure()

        XCTAssertNil(controller.space)
        XCTAssertNil(controller.pendingShelf)
        XCTAssertFalse(controller.hasWorkingChanges)
        XCTAssertFalse(controller.isLocalized)
        XCTAssertEqual(restartCount, 1)
        XCTAssertTrue(controller.message.contains("saved space could not be opened"))
        XCTAssertEqual(try Data(contentsOf: store.url), corruptData)
    }

    @MainActor
    func testSavingBeforeMappingPreservesUnsavedWorkAndDoesNotWriteAFile() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Library")
        beginShelfDraft(on: controller)
        let originalSpace = controller.space

        controller.saveSpace()

        XCTAssertEqual(controller.space, originalSpace)
        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertFalse(controller.hasSavedSpace)
        XCTAssertFalse(controller.isSaving)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertNil(try store.load())
    }

    @MainActor
    func testRecordingAndPlacingWithoutCameraTrackingCannotCreateCoordinates() throws {
        let controller = LibrarySpaceController(catalog: [], store: store)
        controller.beginNewSpace(name: "Library")
        beginShelfDraft(on: controller)

        controller.recordRouteStop()
        controller.recordRouteStop()
        controller.placeShelfAtReticle()

        XCTAssertNotNil(controller.pendingShelf)
        XCTAssertEqual(controller.recordedStopCount, 0)
        XCTAssertEqual(controller.space?.shelves.count, 0)
        XCTAssertEqual(controller.space?.bookLocations.count, 0)
        XCTAssertNil(controller.localizationImageData)
        XCTAssertNil(controller.guidance)
        XCTAssertNil(try store.load())
    }

    @MainActor
    private func beginShelfDraft(on controller: LibrarySpaceController) {
        controller.beginPlacingShelf(
            label: "A3",
            row: "Second from top",
            width: 0.9,
            height: 0.3,
            instructions: "Beside the window"
        )
    }
}
