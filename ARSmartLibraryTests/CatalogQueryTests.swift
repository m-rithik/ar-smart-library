import XCTest
@testable import ARSmartLibrary

final class CatalogQueryTests: XCTestCase {
    func testSearchMatchesAllTermsAcrossDetailsIgnoringCaseAndAccents() {
        let book = makeBook(
            id: "match", title: "Les Misérables", author: "Victor Hugo", genre: "Classic",
            summary: "A story of compassion.", keywords: ["révolution"]
        )

        let result = search([book], query: "  MISERABLES\nHUGO classic compassion revolution  ")

        XCTAssertEqual(result.map(\.id), ["match"])
        XCTAssertTrue(search([book], query: "Hugo ocean").isEmpty)
    }

    func testEmptyAndWhitespaceSearchReturnAllBooksInSelectedOrder() {
        let books = [makeBook(id: "b", title: "Beta"), makeBook(id: "a", title: "Alpha")]

        XCTAssertEqual(search(books, query: "").map(\.id), ["a", "b"])
        XCTAssertEqual(search(books, query: " \n\t ").map(\.id), ["a", "b"])
    }

    func testSearchGenreAndLocatedFiltersCombine() {
        let books = [
            makeBook(id: "match", title: "Ocean", genre: "Adventure"),
            makeBook(id: "unlocated", title: "Ocean", genre: "Adventure"),
            makeBook(id: "genre", title: "Ocean", genre: "Poetry"),
            makeBook(id: "query", title: "Forest", genre: "Adventure")
        ]

        let result = search(
            books, query: "ocean", genre: "ADVENTURE", locatedOnly: true,
            locatedBookIDs: ["match", "genre", "query"]
        )

        XCTAssertEqual(result.map(\.id), ["match"])
        XCTAssertTrue(search(books, locatedOnly: true).isEmpty)
        XCTAssertEqual(search(books, genre: "All genres").count, books.count)
    }

    func testGenreMatchIsExactAndAccentInsensitive() {
        let books = [
            makeBook(id: "one", genre: "Poésie"),
            makeBook(id: "two", genre: "Poésie classique")
        ]

        XCTAssertEqual(search(books, genre: " poesie ").map(\.id), ["one"])
    }

    func testTopRatedSortUsesDescendingRatingThenTitle() {
        let books = [
            makeBook(id: "low", title: "Alpha", rating: 3),
            makeBook(id: "zulu", title: "Zulu", rating: 5),
            makeBook(id: "echo", title: "Écho", rating: 5)
        ]

        XCTAssertEqual(search(books, sort: .rating).map(\.id), ["echo", "zulu", "low"])
    }

    func testAuthorSortUsesTitleToBreakTies() {
        let books = [
            makeBook(id: "last", title: "Alpha", author: "Zulu"),
            makeBook(id: "second", title: "Beta", author: "Émile"),
            makeBook(id: "first", title: "Alpha", author: "Emile")
        ]

        XCTAssertEqual(search(books, sort: .author).map(\.id), ["first", "second", "last"])
    }

    func testSortTiesAreIndependentOfInputOrder() {
        let books = [
            makeBook(id: "b", title: "Écho", author: "Adams"),
            makeBook(id: "c", title: "echo", author: "Brown"),
            makeBook(id: "a", title: "Echo", author: "Adams")
        ]

        for sort in CatalogSort.allCases {
            XCTAssertEqual(search(books, sort: sort).map(\.id), ["a", "b", "c"])
            XCTAssertEqual(search(Array(books.reversed()), sort: sort).map(\.id), ["a", "b", "c"])
        }
    }

    private func search(
        _ books: [Book],
        query: String = "",
        genre: String = "",
        locatedOnly: Bool = false,
        locatedBookIDs: Set<String> = [],
        sort: CatalogSort = .title
    ) -> [Book] {
        CatalogQuery.books(
            in: books, query: query, genre: genre, locatedOnly: locatedOnly,
            locatedBookIDs: locatedBookIDs, sort: sort
        )
    }

    private func makeBook(
        id: String,
        title: String = "Book",
        author: String = "Author",
        genre: String = "Classic",
        rating: Double = 4,
        summary: String = "",
        keywords: [String] = []
    ) -> Book {
        Book(
            id: id, title: title, author: author, genre: genre,
            rating: rating, summary: summary, keywords: keywords
        )
    }
}
