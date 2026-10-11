import Foundation

struct BookMatcher {
    private let books: [Book]

    init(books: [Book]) {
        self.books = books
    }

    func bestMatch(for recognizedLines: [RecognizedLine]) -> BookMatch? {
        let usefulLines = recognizedLines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usefulLines.isEmpty else {
            return nil
        }

        let scannedText = usefulLines.map(\.text).joined(separator: " ")
        let normalizedScan = Self.normalize(scannedText)
        let scanTokens = Set(Self.tokens(in: normalizedScan))

        let rankedMatches = books.map { book -> BookMatch in
            let normalizedTitle = Self.normalize(book.title)
            let titleTokens = Set(Self.tokens(in: normalizedTitle))
            let authorTokens = Set(Self.tokens(in: Self.normalize(book.author)))
            let distinctiveTitleTokens = titleTokens.subtracting(Self.weakEvidenceTokens)
            let evidenceTokens = distinctiveTitleTokens.isEmpty ? titleTokens : distinctiveTitleTokens
            let titleEvidence = Self.strongestTitleEvidence(
                in: usefulLines,
                normalizedTitle: normalizedTitle,
                evidenceTokens: evidenceTokens
            )
            let titleOCRConfidence = titleEvidence?.line.confidence ?? 0
            let localizedTitleCoverage = titleEvidence?.coverage ?? 0

            let titleCoverage = Self.coverage(of: evidenceTokens, in: scanTokens)
            let authorCoverage = Self.coverage(of: authorTokens, in: scanTokens)
            let exactTitleBonus = usefulLines.contains {
                Self.normalize($0.text).contains(normalizedTitle)
            } ? 0.22 : 0
            let tokenScore = (0.68 * titleCoverage) + (0.10 * authorCoverage) + exactTitleBonus
            let fuzzyTitleScore = 0.88 * localizedTitleCoverage
            let rawScore = min(1, max(tokenScore, fuzzyTitleScore))
            let confidence = min(1, (0.82 * rawScore) + (0.18 * titleOCRConfidence))

            let sharedTitleWords = titleTokens.intersection(scanTokens).sorted()
            let evidence: String
            if !sharedTitleWords.isEmpty {
                evidence = "Read: \(sharedTitleWords.joined(separator: ", "))"
            } else if localizedTitleCoverage >= 0.72 {
                evidence = "Read a close title match"
            } else {
                evidence = "Weak title evidence"
            }
            let visionTargetPoint = titleEvidence.map {
                CGPoint(x: $0.line.boundingBox.midX, y: $0.line.boundingBox.midY)
            } ?? CGPoint(x: 0.5, y: 0.5)

            return BookMatch(
                book: book,
                confidence: confidence,
                titleOCRConfidence: titleOCRConfidence,
                localizedTitleCoverage: localizedTitleCoverage,
                visionTargetPoint: visionTargetPoint,
                evidence: evidence
            )
        }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.book.title < $1.book.title
            }
            return $0.confidence > $1.confidence
        }

        guard
            let best = rankedMatches.first,
            best.confidence >= 0.50,
            best.titleOCRConfidence >= 0.45
        else {
            return nil
        }

        if rankedMatches.count > 1, best.confidence - rankedMatches[1].confidence < 0.06 {
            return BookMatch(
                book: best.book,
                confidence: min(best.confidence, 0.64),
                titleOCRConfidence: best.titleOCRConfidence,
                localizedTitleCoverage: best.localizedTitleCoverage,
                visionTargetPoint: best.visionTargetPoint,
                evidence: "Similar titles detected"
            )
        }

        return best
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func tokens(in value: String) -> [String] {
        value.split(separator: " ").map(String.init).filter { $0.count >= 2 }
    }

    private static func coverage(of expected: Set<String>, in observed: Set<String>) -> Double {
        guard !expected.isEmpty else {
            return 0
        }
        return Double(expected.intersection(observed).count) / Double(expected.count)
    }

    private static func strongestTitleEvidence(
        in lines: [RecognizedLine],
        normalizedTitle: String,
        evidenceTokens: Set<String>
    ) -> (line: RecognizedLine, coverage: Double)? {
        lines.compactMap { line -> (line: RecognizedLine, coverage: Double, score: Double)? in
            let normalizedLine = normalize(line.text)
            let lineTokens = Set(tokens(in: normalizedLine))
            let tokenCoverage = Self.coverage(of: evidenceTokens, in: lineTokens)
            let phraseSimilarity = Self.normalizedEditSimilarity(
                Self.distinctivePhrase(in: normalizedLine),
                Self.distinctivePhrase(in: normalizedTitle)
            )
            guard tokenCoverage > 0 || phraseSimilarity >= 0.72 else {
                return nil
            }

            let localizedCoverage = max(tokenCoverage, phraseSimilarity >= 0.72 ? phraseSimilarity : 0)
            let exactLineBonus = normalizedLine.contains(normalizedTitle) ? 2.0 : 0
            let centerDistance = hypot(line.boundingBox.midX - 0.5, line.boundingBox.midY - 0.5)
            let score = exactLineBonus
                + (1.2 * localizedCoverage)
                + (0.2 * line.confidence)
                - (0.15 * min(centerDistance, 1))
            return (line, localizedCoverage, score)
        }
        .max { $0.score < $1.score }
        .map { ($0.line, $0.coverage) }
    }

    private static func normalizedEditSimilarity(_ first: String, _ second: String) -> Double {
        guard !first.isEmpty, !second.isEmpty else {
            return 0
        }

        let firstCharacters = Array(first)
        let secondCharacters = Array(second)
        var previousRow = Array(0 ... secondCharacters.count)

        for (firstIndex, firstCharacter) in firstCharacters.enumerated() {
            var currentRow = [firstIndex + 1]
            for (secondIndex, secondCharacter) in secondCharacters.enumerated() {
                let insertion = currentRow[secondIndex] + 1
                let deletion = previousRow[secondIndex + 1] + 1
                let substitution = previousRow[secondIndex] + (firstCharacter == secondCharacter ? 0 : 1)
                currentRow.append(min(insertion, deletion, substitution))
            }
            previousRow = currentRow
        }

        let distance = previousRow[secondCharacters.count]
        let longestLength = max(firstCharacters.count, secondCharacters.count)
        return 1 - (Double(distance) / Double(longestLength))
    }

    private static func distinctivePhrase(in value: String) -> String {
        let distinctiveTokens = tokens(in: value).filter { !weakEvidenceTokens.contains($0) }
        return distinctiveTokens.isEmpty ? value : distinctiveTokens.joined(separator: " ")
    }

    private static let weakEvidenceTokens: Set<String> = [
        "a", "an", "and", "for", "in", "of", "on", "the", "to"
    ]
}

struct RecognizedLine: Equatable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect

    init(
        text: String,
        confidence: Double,
        boundingBox: CGRect = CGRect(x: 0.49, y: 0.49, width: 0.02, height: 0.02)
    ) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
