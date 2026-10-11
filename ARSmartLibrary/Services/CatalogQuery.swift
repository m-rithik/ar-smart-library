import Foundation

enum CatalogSort: String, CaseIterable, Identifiable {
    case title
    case author
    case rating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .author:
            return "Author"
        case .rating:
            return "Top rated"
        }
    }
}

enum CatalogQuery {
    static func books(
        in books: [Book],
        query: String,
        genre: String,
        locatedOnly: Bool,
        locatedBookIDs: Set<String>,
        sort: CatalogSort
    ) -> [Book] {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace)
        let selectedGenre = normalized(genre.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtersGenre = !selectedGenre.isEmpty && selectedGenre != "all genres"

        return books.filter { book in
            guard !locatedOnly || locatedBookIDs.contains(book.id) else { return false }
            guard !filtersGenre || normalized(book.genre) == selectedGenre else { return false }
            let details = normalized(
                ([book.title, book.author, book.genre, book.summary] + book.keywords).joined(separator: " ")
            )
            return terms.allSatisfy { details.contains($0) }
        }.sorted { left, right in
            if sort == .rating, left.rating != right.rating {
                return left.rating > right.rating
            }
            let leftTitle = normalized(left.title)
            let rightTitle = normalized(right.title)
            let leftAuthor = normalized(left.author)
            let rightAuthor = normalized(right.author)
            if sort == .author, leftAuthor != rightAuthor {
                return leftAuthor < rightAuthor
            }
            if leftTitle != rightTitle {
                return leftTitle < rightTitle
            }
            if leftAuthor != rightAuthor {
                return leftAuthor < rightAuthor
            }
            return left.id < right.id
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
