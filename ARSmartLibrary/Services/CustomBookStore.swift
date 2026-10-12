import Foundation

final class CustomBookStore {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? URL.applicationSupportDirectory
            .appendingPathComponent("ARSmartLibrary", isDirectory: true)
            .appendingPathComponent("custom-books.json")
    }

    func load() throws -> [Book] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let books = try JSONDecoder().decode([Book].self, from: Data(contentsOf: url))
        try Self.validate(books)
        return books
    }

    func save(_ books: [Book]) throws {
        try Self.validate(books)
        let data = try JSONEncoder().encode(books)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func makeBook(
        title: String,
        author: String,
        genre: String,
        summary: String,
        keywords: String,
        rating: Double,
        existingBooks: [Book]
    ) throws -> Book {
        var seenKeywords = Set<String>()
        let cleanedKeywords = keywords.split(separator: ",").map { trimmed(String($0)) }.filter {
            !$0.isEmpty && seenKeywords.insert(BookMatcher.normalize($0)).inserted
        }
        let book = Book(
            id: "custom-\(UUID().uuidString.lowercased())",
            title: trimmed(title),
            author: trimmed(author),
            genre: trimmed(genre).isEmpty ? "Uncategorized" : trimmed(genre),
            rating: rating,
            summary: trimmed(summary),
            keywords: cleanedKeywords
        )
        try validate([book])
        guard !existingBooks.contains(where: { identity(for: $0) == identity(for: book) }) else {
            throw CustomBookError.duplicateBook
        }
        return book
    }

    private static func validate(_ books: [Book]) throws {
        var ids = Set<String>()
        var identities = Set<[String]>()
        for book in books {
            guard book.id.hasPrefix("custom-"), UUID(uuidString: String(book.id.dropFirst(7))) != nil,
                  ids.insert(book.id).inserted else {
                throw CustomBookError.invalidStoredBook
            }
            guard !trimmed(book.title).isEmpty else { throw CustomBookError.titleRequired }
            guard !BookMatcher.normalize(book.title).isEmpty else { throw CustomBookError.invalidTitle }
            guard !trimmed(book.author).isEmpty else { throw CustomBookError.authorRequired }
            guard book.rating.isFinite, (0...5).contains(book.rating) else { throw CustomBookError.invalidRating }
            guard !trimmed(book.genre).isEmpty,
                  book.keywords.allSatisfy({ !trimmed($0).isEmpty }),
                  Set(book.keywords).count == book.keywords.count else {
                throw CustomBookError.invalidStoredBook
            }
            guard identities.insert(identity(for: book)).inserted else { throw CustomBookError.duplicateBook }
        }
    }

    private static func identity(for book: Book) -> [String] {
        [BookMatcher.normalize(book.title), BookMatcher.normalize(book.author)]
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CustomBookError: Error, LocalizedError, Equatable {
    case titleRequired
    case invalidTitle
    case authorRequired
    case invalidRating
    case duplicateBook
    case invalidStoredBook
    case storageUnavailable
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .titleRequired: return "Enter the book title."
        case .invalidTitle: return "The title needs letters or numbers so it can be recognized."
        case .authorRequired: return "Enter the book's author."
        case .invalidRating: return "Choose a rating from 0 to 5. Zero means unrated."
        case .duplicateBook: return "A book with this title and author is already in the catalog."
        case .invalidStoredBook: return "The custom book data is invalid. The existing file has been kept."
        case .storageUnavailable: return "Custom book storage is unavailable."
        case .loadFailed: return "Your saved books could not be opened. Adding books is disabled to protect the saved file."
        }
    }
}
