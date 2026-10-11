import XCTest
@testable import ARSmartLibrary

final class BookCatalogTests: XCTestCase {
    func testBundledCatalogLoadsWithUniqueIdentifiers() {
        let books = BookCatalog.load()

        XCTAssertEqual(books.count, 12)
        XCTAssertEqual(Set(books.map(\.id)).count, books.count)
        XCTAssertTrue(books.allSatisfy { !$0.title.isEmpty && !$0.author.isEmpty })
    }
}
