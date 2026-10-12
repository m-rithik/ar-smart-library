import Foundation
import XCTest
@testable import ARSmartLibrary

final class CustomBookStoreTests: XCTestCase {
    private var directory: URL!
    private var store: CustomBookStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CustomBookStore(url: directory.appendingPathComponent("custom-books.json"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testRoundTripPreservesCustomBookIdentifiersAndDetails() throws {
        let first = try makeBook(title: "First book", rating: 0)
        let second = try makeBook(title: "Second book", rating: 4.5)

        try store.save([first, second])
        let restored = CustomBookStore(url: store.url)

        XCTAssertEqual(try restored.load(), [first, second])
        XCTAssertTrue(first.id.hasPrefix("custom-"))
        XCTAssertNotNil(UUID(uuidString: String(first.id.dropFirst(7))))
        XCTAssertNotEqual(first.id, second.id)
        try restored.save([second, first])
        XCTAssertEqual(try store.load().map(\.id), [second.id, first.id])
    }

    func testInputTrimmingDefaultsAndKeywordDeduplication() throws {
        let book = try CustomBookStore.makeBook(
            title: "  My Book\n", author: " Author \n", genre: " \n", summary: "  A summary.  ",
            keywords: " Science, science, , Exploration , café, CAFE, ", rating: 0, existingBooks: []
        )

        XCTAssertEqual(book.title, "My Book")
        XCTAssertEqual(book.author, "Author")
        XCTAssertEqual(book.genre, "Uncategorized")
        XCTAssertEqual(book.summary, "A summary.")
        XCTAssertEqual(book.keywords, ["Science", "Exploration", "café"])
        XCTAssertEqual(book.rating, 0)
        XCTAssertEqual(try makeBook().summary, "")
    }

    func testRequiredFieldsAndUnrecognizableTitlesAreRejected() {
        XCTAssertThrowsError(try makeBook(title: " \n ")) { error in
            XCTAssertEqual(error as? CustomBookError, .titleRequired)
        }
        XCTAssertThrowsError(try makeBook(title: " …📚! ")) { error in
            XCTAssertEqual(error as? CustomBookError, .invalidTitle)
        }
        XCTAssertThrowsError(try makeBook(author: " \n ")) { error in
            XCTAssertEqual(error as? CustomBookError, .authorRequired)
        }
    }

    func testNormalizedDuplicatesAgainstCustomAndBundledBooksAreRejected() throws {
        let existing = try makeBook(title: "Les Misérables", author: "Victor Hugo")
        XCTAssertThrowsError(try makeBook(title: "LES MISERABLES!", author: "victor  hugo", existingBooks: [existing])) { error in
            XCTAssertEqual(error as? CustomBookError, .duplicateBook)
        }

        let catalog = BookCatalog.load()
        let bundled = try XCTUnwrap(catalog.first)
        XCTAssertThrowsError(try makeBook(title: bundled.title.uppercased(), author: bundled.author, existingBooks: catalog)) { error in
            XCTAssertEqual(error as? CustomBookError, .duplicateBook)
        }
        XCTAssertNoThrow(try makeBook(title: existing.title, author: "Different Author", existingBooks: [existing]))
    }

    func testInvalidRatingsAreRejectedAndEndpointsAreAccepted() throws {
        for rating in [-0.1, 5.1, Double.infinity, -.infinity, .nan] {
            XCTAssertThrowsError(try makeBook(rating: rating)) { error in
                XCTAssertEqual(error as? CustomBookError, .invalidRating)
            }
        }
        XCTAssertEqual(try makeBook(rating: 0).rating, 0)
        XCTAssertEqual(try makeBook(rating: 5).rating, 5)
    }

    func testMissingFileReturnsEmptyWithoutCreatingIt() throws {
        XCTAssertEqual(try store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testMalformedFileIsNotOverwrittenByLoad() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("not valid JSON".utf8)
        try corrupt.write(to: store.url)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
    }

    func testLoadRejectsInvalidIdentifiersDuplicateRecordsAndInvalidDetails() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let valid = try makeBook()
        let invalidLists = [
            [storedBook(id: "bundled-id")],
            [storedBook(id: "custom-not-a-uuid")],
            [valid, valid],
            [valid, storedBook(title: valid.title, author: valid.author)],
            [storedBook(title: "?!")],
            [storedBook(author: " ")],
            [storedBook(rating: 6)],
            [storedBook(genre: " ")],
            [storedBook(keywords: ["theme", "theme"])],
            [storedBook(keywords: [" "])]
        ]
        for books in invalidLists {
            let data = try JSONEncoder().encode(books)
            try data.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), data)
        }
    }

    func testInvalidSavePreservesTheExistingFile() throws {
        let valid = try makeBook()
        try store.save([valid])
        let original = try Data(contentsOf: store.url)

        XCTAssertThrowsError(try store.save([storedBook(rating: .nan)]))
        XCTAssertThrowsError(try store.save([valid, valid]))

        XCTAssertEqual(try Data(contentsOf: store.url), original)
        XCTAssertEqual(try store.load(), [valid])
    }

    func testFailedWritePreservesDestinationContents() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("keep.txt")
        let data = Data("Keep this file".utf8)
        try data.write(to: marker)
        let invalidStore = CustomBookStore(url: directory)

        XCTAssertThrowsError(try invalidStore.save([makeBook()]))
        XCTAssertEqual(try Data(contentsOf: marker), data)
    }

    private func makeBook(
        title: String = "Custom book", author: String = "Custom Author", rating: Double = 0,
        existingBooks: [Book] = []
    ) throws -> Book {
        try CustomBookStore.makeBook(
            title: title, author: author, genre: "", summary: "", keywords: "",
            rating: rating, existingBooks: existingBooks
        )
    }

    private func storedBook(
        id: String = "custom-\(UUID().uuidString)", title: String = "Book", author: String = "Author",
        rating: Double = 0, genre: String = "Uncategorized", keywords: [String] = []
    ) -> Book {
        Book(id: id, title: title, author: author, genre: genre, rating: rating, summary: "", keywords: keywords)
    }
}
