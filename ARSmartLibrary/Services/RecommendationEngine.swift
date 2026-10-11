import Foundation

struct RecommendationEngine {
    func recommendations(
        for seed: Book,
        from catalog: [Book],
        intent: RecommendationIntent = .similar,
        limit: Int = 3
    ) -> [BookRecommendation] {
        guard limit > 0 else {
            return []
        }

        let model = TFIDFContentModel(catalog: catalog)
        let candidates = catalog
            .filter { $0.id != seed.id }
            .compactMap { candidate -> RankedCandidate? in
                let semanticSimilarity = model.similarity(between: seed, and: candidate)
                let sharedThemes = Self.sharedThemes(between: seed, and: candidate)
                guard semanticSimilarity >= 0.06 || !sharedThemes.isEmpty else {
                    return nil
                }

                let normalizedRating = min(max(candidate.rating / 5, 0), 1)
                let changesGenre = seed.genre.caseInsensitiveCompare(candidate.genre) != .orderedSame
                let baseScore: Double

                switch intent {
                case .similar:
                    baseScore = (0.88 * semanticSimilarity) + (0.12 * normalizedRating)
                case .explore:
                    baseScore = (0.52 * semanticSimilarity)
                        + (changesGenre ? 0.28 : 0)
                        + (!sharedThemes.isEmpty ? 0.12 : 0)
                        + (0.08 * normalizedRating)
                case .highlyRated:
                    baseScore = (0.55 * semanticSimilarity) + (0.45 * normalizedRating)
                }

                return RankedCandidate(
                    book: candidate,
                    baseScore: baseScore,
                    sharedThemes: sharedThemes
                )
            }

        let ranked = intent == .explore
            ? Self.diversified(candidates, model: model, limit: limit)
            : candidates.sorted(by: Self.ranksBefore).prefix(limit).map { $0 }

        return ranked.map { candidate in
            BookRecommendation(
                book: candidate.book,
                score: candidate.baseScore,
                reason: Self.reason(
                    seed: seed,
                    candidate: candidate,
                    intent: intent
                )
            )
        }
    }

    func comparison(between first: Book, and second: Book, in catalog: [Book]) -> BookComparison {
        var modelCatalog = catalog
        if !modelCatalog.contains(where: { $0.id == first.id }) {
            modelCatalog.append(first)
        }
        if !modelCatalog.contains(where: { $0.id == second.id }) {
            modelCatalog.append(second)
        }

        return BookComparison(
            first: first,
            second: second,
            similarity: TFIDFContentModel(catalog: modelCatalog).similarity(between: first, and: second),
            sharedThemes: Self.sharedThemes(between: first, and: second)
        )
    }

    private static func diversified(
        _ candidates: [RankedCandidate],
        model: TFIDFContentModel,
        limit: Int
    ) -> [RankedCandidate] {
        var remaining = candidates
        var selected: [RankedCandidate] = []

        while !remaining.isEmpty, selected.count < limit {
            let next = remaining.max { left, right in
                let leftScore = diversityScore(for: left, selected: selected, model: model)
                let rightScore = diversityScore(for: right, selected: selected, model: model)
                if leftScore == rightScore {
                    return ranksBefore(right, left)
                }
                return leftScore < rightScore
            }
            guard let next else {
                break
            }

            selected.append(next)
            remaining.removeAll { $0.book.id == next.book.id }
        }

        return selected
    }

    private static func diversityScore(
        for candidate: RankedCandidate,
        selected: [RankedCandidate],
        model: TFIDFContentModel
    ) -> Double {
        let redundancy = selected
            .map { model.similarity(between: candidate.book, and: $0.book) }
            .max() ?? 0
        return candidate.baseScore - (0.28 * redundancy)
    }

    private static func ranksBefore(_ left: RankedCandidate, _ right: RankedCandidate) -> Bool {
        if left.baseScore == right.baseScore {
            if left.book.rating == right.book.rating {
                return left.book.title < right.book.title
            }
            return left.book.rating > right.book.rating
        }
        return left.baseScore > right.baseScore
    }

    private static func sharedThemes(between first: Book, and second: Book) -> [String] {
        let firstThemes = Set(first.keywords.map { $0.lowercased() })
        let secondThemes = Set(second.keywords.map { $0.lowercased() })
        return firstThemes.intersection(secondThemes).sorted()
    }

    private static func reason(
        seed: Book,
        candidate: RankedCandidate,
        intent: RecommendationIntent
    ) -> String {
        let themes = candidate.sharedThemes.prefix(2).joined(separator: " and ")

        switch intent {
        case .similar:
            if !themes.isEmpty {
                return "Connects through \(themes)."
            }
            if seed.genre.caseInsensitiveCompare(candidate.book.genre) == .orderedSame {
                return "A related \(candidate.book.genre.lowercased()) read."
            }
            return "Similar language and subject matter."
        case .explore:
            if seed.genre.caseInsensitiveCompare(candidate.book.genre) != .orderedSame {
                return themes.isEmpty
                    ? "A broader jump into \(candidate.book.genre.lowercased())."
                    : "A different genre connected by \(themes)."
            }
            return themes.isEmpty
                ? "A less obvious \(candidate.book.genre.lowercased()) pick."
                : "A less obvious pick linked by \(themes)."
        case .highlyRated:
            if !themes.isEmpty {
                return "Rated \(candidate.book.rating.formatted(.number.precision(.fractionLength(1)))) and linked by \(themes)."
            }
            return "A related pick rated \(candidate.book.rating.formatted(.number.precision(.fractionLength(1))))."
        }
    }
}

private struct RankedCandidate {
    let book: Book
    let baseScore: Double
    let sharedThemes: [String]
}

private struct TFIDFContentModel {
    private let vectorsByBookID: [String: [String: Double]]

    init(catalog: [Book]) {
        let termFrequencies = Dictionary(
            uniqueKeysWithValues: catalog.map { ($0.id, Self.termFrequencies(for: $0)) }
        )
        var documentFrequency: [String: Int] = [:]
        for terms in termFrequencies.values {
            for term in terms.keys {
                documentFrequency[term, default: 0] += 1
            }
        }

        let documentCount = Double(max(catalog.count, 1))
        vectorsByBookID = termFrequencies.mapValues { terms in
            terms.reduce(into: [String: Double]()) { vector, entry in
                let frequency = entry.value
                let documentsWithTerm = Double(documentFrequency[entry.key] ?? 0)
                let inverseDocumentFrequency = log((documentCount + 1) / (documentsWithTerm + 1)) + 1
                vector[entry.key] = log1p(frequency) * inverseDocumentFrequency
            }
        }
    }

    func similarity(between first: Book, and second: Book) -> Double {
        guard
            let firstVector = vectorsByBookID[first.id],
            let secondVector = vectorsByBookID[second.id]
        else {
            return 0
        }

        let sharedTerms = Set(firstVector.keys).intersection(secondVector.keys)
        let dotProduct = sharedTerms.reduce(0) {
            $0 + ((firstVector[$1] ?? 0) * (secondVector[$1] ?? 0))
        }
        let firstMagnitude = sqrt(firstVector.values.reduce(0) { $0 + ($1 * $1) })
        let secondMagnitude = sqrt(secondVector.values.reduce(0) { $0 + ($1 * $1) })
        guard firstMagnitude > 0, secondMagnitude > 0 else {
            return 0
        }
        return min(max(dotProduct / (firstMagnitude * secondMagnitude), 0), 1)
    }

    private static func termFrequencies(for book: Book) -> [String: Double] {
        var frequencies: [String: Double] = [:]

        add(tokens(in: book.title), weight: 1.2, to: &frequencies)
        add(tokens(in: book.author), weight: 0.35, to: &frequencies)
        add(tokens(in: book.summary), weight: 0.8, to: &frequencies)
        add(tokens(in: book.genre), weight: 1.4, to: &frequencies)

        let normalizedGenre = normalized(book.genre).replacingOccurrences(of: " ", with: "_")
        if !normalizedGenre.isEmpty {
            frequencies["genre:\(normalizedGenre)", default: 0] += 2.4
        }

        for keyword in book.keywords {
            let normalizedKeyword = normalized(keyword).replacingOccurrences(of: " ", with: "_")
            if !normalizedKeyword.isEmpty {
                frequencies["theme:\(normalizedKeyword)", default: 0] += 3.0
            }
            add(tokens(in: keyword), weight: 1.8, to: &frequencies)
        }

        return frequencies
    }

    private static func add(
        _ terms: [String],
        weight: Double,
        to frequencies: inout [String: Double]
    ) {
        for term in terms {
            frequencies[term, default: 0] += weight
        }
    }

    private static func tokens(in value: String) -> [String] {
        normalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static let stopwords: Set<String> = [
        "a", "an", "and", "as", "at", "by", "for", "from", "in", "into", "is", "it",
        "of", "on", "or", "the", "their", "to", "while", "with"
    ]
}
