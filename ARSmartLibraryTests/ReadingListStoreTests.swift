import XCTest
@testable import ARSmartLibrary

@MainActor
final class ReadingListStoreTests: XCTestCase {
    func testStatusesPersistAcrossStoreInstances() throws {
        let suiteName = "ReadingListStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReadingListStore(defaults: defaults)

        XCTAssertTrue(store.statuses.isEmpty)
        store.setStatus(.wantToRead, for: "first")
        store.setStatus(.reading, for: "second")
        store.setStatus(.finished, for: "third")

        let restored = ReadingListStore(defaults: defaults)
        XCTAssertEqual(restored.statuses, ["first": .wantToRead, "second": .reading, "third": .finished])
        XCTAssertNil(restored.status(for: "unknown"))
    }

    func testChangingAndRemovingStatusPreservesOtherBooks() throws {
        let suiteName = "ReadingListStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReadingListStore(defaults: defaults)
        store.setStatus(.wantToRead, for: "first")
        store.setStatus(.reading, for: "second")

        store.setStatus(.finished, for: "first")
        XCTAssertEqual(ReadingListStore(defaults: defaults).status(for: "first"), .finished)
        store.setStatus(nil, for: "first")

        XCTAssertEqual(store.statuses, ["second": .reading])
        XCTAssertEqual(ReadingListStore(defaults: defaults).statuses, ["second": .reading])
        store.setStatus(nil, for: "second")
        XCTAssertTrue(ReadingListStore(defaults: defaults).statuses.isEmpty)
    }

    func testUnknownOrMalformedSavedStatusesDoNotDiscardValidEntries() throws {
        let suiteName = "ReadingListStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ["valid": "reading", "future": "paused", "malformed": 12] as [String: Any],
            forKey: "reading-list-statuses-v1"
        )

        XCTAssertEqual(ReadingListStore(defaults: defaults).statuses, ["valid": .reading])
    }
}
