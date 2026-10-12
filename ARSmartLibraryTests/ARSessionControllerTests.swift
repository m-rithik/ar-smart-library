import ARKit
import XCTest
@testable import ARSmartLibrary

final class ARSessionControllerTests: XCTestCase {
    @MainActor
    func testNewCustomBookIsRecognizedImmediatelyAndAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let customStore = CustomBookStore(url: directory.appendingPathComponent("custom-books.json"))
        let controller = ARSessionController(
            customBookStore: customStore,
            spaceStore: LibrarySpaceStore(url: directory.appendingPathComponent("library-space.json"))
        )
        let lines = [RecognizedLine(
            text: "Celestial Orchards", confidence: 0.99,
            boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.2)
        )]
        XCTAssertNil(controller.matcher.bestMatch(for: lines))
        let book = try controller.librarySpace.addCustomBook(
            title: "Celestial Orchards", author: "Mira Sen", genre: "Fiction",
            summary: "", keywords: "", rating: 0
        )

        XCTAssertEqual(controller.matcher.bestMatch(for: lines)?.book, book)
        let reloaded = ARSessionController(
            customBookStore: customStore,
            spaceStore: LibrarySpaceStore(url: directory.appendingPathComponent("library-space.json"))
        )
        XCTAssertEqual(reloaded.matcher.bestMatch(for: lines)?.book, book)
    }

    @MainActor
    func testFreshNormalFrameRestoresTrackingAfterPauseWithoutStateChange() {
        let controller = ARSessionController(customBookStore: nil)
        XCTAssertTrue(controller.updateTrackingReadiness(.normal, at: 10))
        XCTAssertTrue(controller.isTrackingNormally)

        controller.pause()

        XCTAssertFalse(controller.isTrackingNormally)
        XCTAssertFalse(controller.updateTrackingReadiness(.normal, at: 9))
        XCTAssertFalse(controller.updateTrackingReadiness(.normal, at: 10))
        XCTAssertFalse(controller.isTrackingNormally)
        XCTAssertTrue(controller.updateTrackingReadiness(.normal, at: 11))
        XCTAssertTrue(controller.isTrackingNormally)
    }

    @MainActor
    func testFreshNormalFrameRestoresTrackingAfterInterruptionWithoutStateChange() async {
        let controller = ARSessionController(customBookStore: nil)
        controller.updateTrackingReadiness(.normal, at: 10)

        controller.sessionWasInterrupted(ARSession())
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        XCTAssertFalse(controller.isTrackingNormally)
        XCTAssertFalse(controller.updateTrackingReadiness(.normal, at: 10))
        XCTAssertFalse(controller.isTrackingNormally)
        XCTAssertTrue(controller.updateTrackingReadiness(.normal, at: 11))
        XCTAssertTrue(controller.isTrackingNormally)
        XCTAssertNotEqual(controller.statusMessage, "AR session paused")
    }

    @MainActor
    func testLimitedFrameSuspendsTrackingAndOlderNormalFrameCannotRestoreIt() {
        let controller = ARSessionController(customBookStore: nil)
        controller.updateTrackingReadiness(.normal, at: 10)

        XCTAssertTrue(controller.updateTrackingReadiness(.limited(.excessiveMotion), at: 11))

        XCTAssertFalse(controller.isTrackingNormally)
        XCTAssertFalse(controller.updateTrackingReadiness(.normal, at: 10.5))
        XCTAssertFalse(controller.isTrackingNormally)
        XCTAssertTrue(controller.updateTrackingReadiness(.normal, at: 12))
        XCTAssertTrue(controller.isTrackingNormally)
    }

    @MainActor
    func testFailureKeepsDraftUntilUserChoosesToRestart() async throws {
        let controller = ARSessionController(customBookStore: nil)
        controller.librarySpace.beginNewSpace(name: "Working library")
        controller.librarySpace.beginPlacingShelf(
            label: "A3", row: "Middle", width: 0.9, height: 0.3, instructions: ""
        )
        let workingSpace = controller.librarySpace.space
        var restartCount = 0
        controller.librarySpace.restartSession = { restartCount += 1 }

        controller.session(ARSession(), didFailWithError: NSError(
            domain: "ARSmartLibraryTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Camera interrupted"]
        ))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        XCTAssertEqual(controller.sessionFailureMessage, "Camera interrupted")
        XCTAssertFalse(controller.canUseAR)
        XCTAssertEqual(controller.librarySpace.space, workingSpace)
        XCTAssertNotNil(controller.librarySpace.pendingShelf)
        XCTAssertTrue(controller.librarySpace.hasWorkingChanges)
        XCTAssertEqual(restartCount, 0)
    }

    @MainActor
    func testRetryWithoutFailureDoesNotResetWorkingSpace() {
        let controller = ARSessionController(customBookStore: nil)
        controller.librarySpace.beginNewSpace(name: "Working library")
        let workingSpace = controller.librarySpace.space
        var restartCount = 0
        controller.librarySpace.restartSession = { restartCount += 1 }

        controller.retryARSession()

        XCTAssertEqual(restartCount, 0)
        XCTAssertEqual(controller.librarySpace.space, workingSpace)
    }

    @MainActor
    func testMeshCannotBeEnabledWithoutLiDAR() {
        let controller = ARSessionController(customBookStore: nil)
        controller.toggleMeshVisualization()
        XCTAssertFalse(controller.meshVisible)
    }
}
