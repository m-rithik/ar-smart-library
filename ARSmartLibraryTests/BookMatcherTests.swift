import XCTest
@testable import ARSmartLibrary

final class BookMatcherTests: XCTestCase {
    private let catalog = [
        Book(
            id: "frankenstein",
            title: "Frankenstein",
            author: "Mary Shelley",
            genre: "Gothic",
            rating: 4.4,
            summary: "Summary",
            keywords: ["science", "identity"]
        ),
        Book(
            id: "dracula",
            title: "Dracula",
            author: "Bram Stoker",
            genre: "Gothic",
            rating: 4.3,
            summary: "Summary",
            keywords: ["fear", "identity"]
        ),
        Book(
            id: "the-time-machine",
            title: "The Time Machine",
            author: "H. G. Wells",
            genre: "Science Fiction",
            rating: 4.2,
            summary: "Summary",
            keywords: ["time", "future"]
        )
    ]

    func testMatchesExactTitleAndAuthor() throws {
        let matcher = BookMatcher(books: catalog)

        let match = try XCTUnwrap(
            matcher.bestMatch(
                for: [
                    RecognizedLine(text: "FRANKENSTEIN", confidence: 0.95),
                    RecognizedLine(text: "Mary Shelley", confidence: 0.90)
                ]
            )
        )

        XCTAssertEqual(match.book.id, "frankenstein")
        XCTAssertGreaterThan(match.confidence, 0.75)
        XCTAssertEqual(match.titleOCRConfidence, 0.95, accuracy: 0.001)
    }

    func testRejectsTextOutsideCatalog() {
        let matcher = BookMatcher(books: catalog)

        let match = matcher.bestMatch(
            for: [RecognizedLine(text: "Organic Chemistry Laboratory Manual", confidence: 0.92)]
        )

        XCTAssertNil(match)
    }

    func testNormalizationRemovesCasePunctuationAndDiacritics() {
        XCTAssertEqual(
            BookMatcher.normalize("  JANE—EYRE: Brontë! "),
            "jane eyre bronte"
        )
    }

    func testRejectsLowConfidenceExactTitle() {
        let matcher = BookMatcher(books: catalog)

        let match = matcher.bestMatch(
            for: [RecognizedLine(text: "FRANKENSTEIN", confidence: 0.25)]
        )

        XCTAssertNil(match)
    }

    func testRecoversSingleCharacterOCRSubstitution() throws {
        let matcher = BookMatcher(books: catalog)

        let match = try XCTUnwrap(
            matcher.bestMatch(
                for: [RecognizedLine(text: "FRANKENSTELN", confidence: 0.92)]
            )
        )

        XCTAssertEqual(match.book.id, "frankenstein")
        XCTAssertGreaterThan(match.confidence, 0.7)
    }

    func testSharedCommonWordsCannotConfirmADifferentTitle() {
        let matcher = BookMatcher(books: BookCatalog.load())

        for title in ["The Art of War", "The War of Art", "The War of the Roses"] {
            let match = matcher.bestMatch(for: [RecognizedLine(text: title, confidence: 0.99)])

            XCTAssertLessThan(
                match?.confidence ?? 0,
                ScanCandidateTracker.minimumConfidence,
                "A different title must not qualify for a scan result: \(title)"
            )
        }
    }

    func testEveryBundledExactTitleStillSupportsExactMatching() throws {
        let books = BookCatalog.load()
        XCTAssertFalse(books.isEmpty)
        let matcher = BookMatcher(books: books)

        for book in books {
            let match = try XCTUnwrap(matcher.bestMatch(
                for: [RecognizedLine(text: book.title, confidence: 0.99)]
            ))

            XCTAssertEqual(match.book.id, book.id)
            XCTAssertGreaterThanOrEqual(match.confidence, ScanCandidateTracker.minimumExactConfidence)
            XCTAssertGreaterThanOrEqual(
                match.localizedTitleCoverage,
                ScanCandidateTracker.minimumExactTitleCoverage
            )
        }
    }

    func testDistinctiveTitleWordsStillMatchWithAnOCRTypo() throws {
        let matcher = BookMatcher(books: BookCatalog.load())
        let match = try XCTUnwrap(matcher.bestMatch(
            for: [RecognizedLine(text: "The War of the Wor1ds", confidence: 0.95)]
        ))

        XCTAssertEqual(match.book.id, "the-war-of-the-worlds")
        XCTAssertGreaterThanOrEqual(match.confidence, ScanCandidateTracker.minimumConfidence)
    }

    func testTitleSplitAcrossLinesStillQualifies() throws {
        let matcher = BookMatcher(books: catalog)
        let match = try XCTUnwrap(matcher.bestMatch(for: [
            RecognizedLine(text: "The Time", confidence: 0.95),
            RecognizedLine(text: "Machine", confidence: 0.95)
        ]))

        XCTAssertEqual(match.book.id, "the-time-machine")
        XCTAssertGreaterThanOrEqual(match.confidence, ScanCandidateTracker.minimumConfidence)
    }

    func testTargetPointFollowsMatchedTitleObservation() throws {
        let matcher = BookMatcher(books: catalog)
        let titleBox = CGRect(x: 0.68, y: 0.42, width: 0.2, height: 0.1)

        let match = try XCTUnwrap(
            matcher.bestMatch(
                for: [
                    RecognizedLine(text: "FRANKENSTEIN", confidence: 0.95, boundingBox: titleBox),
                    RecognizedLine(
                        text: "Unrelated label",
                        confidence: 0.99,
                        boundingBox: CGRect(x: 0.05, y: 0.1, width: 0.2, height: 0.1)
                    )
                ]
            )
        )

        XCTAssertEqual(match.visionTargetPoint.x, titleBox.midX, accuracy: 0.001)
        XCTAssertEqual(match.visionTargetPoint.y, titleBox.midY, accuracy: 0.001)
    }

    func testStopwordOnlyLinesCannotInflateOrMoveTitleEvidence() throws {
        let matcher = BookMatcher(books: catalog)
        let titleBox = CGRect(x: 0.66, y: 0.4, width: 0.22, height: 0.1)

        let match = try XCTUnwrap(
            matcher.bestMatch(
                for: [
                    RecognizedLine(text: "The Time Machine", confidence: 0.46, boundingBox: titleBox),
                    RecognizedLine(
                        text: "The library",
                        confidence: 0.99,
                        boundingBox: CGRect(x: 0.05, y: 0.1, width: 0.2, height: 0.1)
                    ),
                    RecognizedLine(
                        text: "The shelf",
                        confidence: 0.99,
                        boundingBox: CGRect(x: 0.15, y: 0.8, width: 0.2, height: 0.1)
                    )
                ]
            )
        )

        XCTAssertEqual(match.book.id, "the-time-machine")
        XCTAssertEqual(match.titleOCRConfidence, 0.46, accuracy: 0.001)
        XCTAssertEqual(match.visionTargetPoint.x, titleBox.midX, accuracy: 0.001)
        XCTAssertEqual(match.visionTargetPoint.y, titleBox.midY, accuracy: 0.001)
    }
}
