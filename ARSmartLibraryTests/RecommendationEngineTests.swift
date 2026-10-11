import XCTest
@testable import ARSmartLibrary

final class RecommendationEngineTests: XCTestCase {
    func testRecommendationsExcludeSeedAndPreferSharedThemes() throws {
        let seed = makeBook(
            id: "seed",
            title: "Seed",
            genre: "Gothic",
            rating: 4.0,
            keywords: ["identity", "science"]
        )
        let closeMatch = makeBook(
            id: "close",
            title: "Close",
            genre: "Gothic",
            rating: 4.1,
            keywords: ["identity", "science", "isolation"]
        )
        let distantMatch = makeBook(
            id: "distant",
            title: "Distant",
            genre: "Adventure",
            rating: 5.0,
            keywords: ["ocean", "survival"]
        )

        let recommendations = RecommendationEngine().recommendations(
            for: seed,
            from: [seed, distantMatch, closeMatch]
        )

        XCTAssertEqual(recommendations.map(\.book.id), ["close"])
        XCTAssertFalse(recommendations.contains { $0.book.id == seed.id })
        XCTAssertTrue(try XCTUnwrap(recommendations.first).reason.contains("identity"))
    }

    func testSummaryTermsInfluenceTFIDFRanking() throws {
        let seed = makeBook(
            id: "seed",
            title: "Seed",
            genre: "Reference",
            rating: 4,
            summary: "An ocean voyage about survival during a dangerous storm.",
            keywords: []
        )
        let related = makeBook(
            id: "related",
            title: "Related",
            genre: "Adventure",
            rating: 3.5,
            summary: "A dangerous voyage across the ocean tests survival.",
            keywords: []
        )
        let unrelated = makeBook(
            id: "unrelated",
            title: "Unrelated",
            genre: "Romance",
            rating: 5,
            summary: "Courtship, manners, and family life in the countryside.",
            keywords: []
        )

        let recommendations = RecommendationEngine().recommendations(
            for: seed,
            from: [seed, unrelated, related]
        )

        XCTAssertEqual(try XCTUnwrap(recommendations.first).book.id, "related")
    }

    func testUnrelatedHighRatingDoesNotCreateRecommendation() {
        let seed = makeBook(
            id: "seed",
            title: "Astronomy Guide",
            genre: "Science",
            rating: 3,
            summary: "Planets orbit distant stars.",
            keywords: ["space"]
        )
        let unrelated = makeBook(
            id: "unrelated",
            title: "Kitchen Basics",
            genre: "Cooking",
            rating: 5,
            summary: "Recipes for bread and soup.",
            keywords: ["food"]
        )

        let recommendations = RecommendationEngine().recommendations(
            for: seed,
            from: [seed, unrelated]
        )

        XCTAssertTrue(recommendations.isEmpty)
    }

    func testExploreIntentIntroducesAGenreBridge() {
        let seed = makeBook(
            id: "seed",
            title: "Seed",
            genre: "Gothic",
            rating: 4,
            keywords: ["identity", "science"]
        )
        let gothicOne = makeBook(
            id: "gothic-one",
            title: "Gothic One",
            genre: "Gothic",
            rating: 4.5,
            keywords: ["identity", "science"]
        )
        let gothicTwo = makeBook(
            id: "gothic-two",
            title: "Gothic Two",
            genre: "Gothic",
            rating: 4.4,
            keywords: ["identity", "science"]
        )
        let scienceFiction = makeBook(
            id: "science-fiction",
            title: "Science Fiction",
            genre: "Science Fiction",
            rating: 4,
            keywords: ["science", "future"]
        )

        let recommendations = RecommendationEngine().recommendations(
            for: seed,
            from: [seed, gothicOne, gothicTwo, scienceFiction],
            intent: .explore,
            limit: 2
        )

        XCTAssertTrue(recommendations.contains { $0.book.id == "science-fiction" })
    }

    func testComparisonUsesModelSimilarityAndSharedThemes() {
        let first = makeBook(
            id: "first",
            title: "First",
            genre: "Gothic",
            rating: 4,
            keywords: ["identity", "science"]
        )
        let second = makeBook(
            id: "second",
            title: "Second",
            genre: "Science Fiction",
            rating: 4,
            keywords: ["science", "future"]
        )
        let unrelated = makeBook(
            id: "unrelated",
            title: "Unrelated",
            genre: "Cooking",
            rating: 4,
            summary: "Bread, soup, recipes, and kitchens.",
            keywords: ["food"]
        )
        let catalog = [first, second, unrelated]

        let comparison = RecommendationEngine().comparison(
            between: first,
            and: second,
            in: catalog
        )
        let unrelatedComparison = RecommendationEngine().comparison(
            between: first,
            and: unrelated,
            in: catalog
        )

        XCTAssertGreaterThan(comparison.similarity, unrelatedComparison.similarity)
        XCTAssertEqual(comparison.sharedThemes, ["science"])
    }

    func testBundledCatalogProducesResultsForEveryIntent() throws {
        let catalog = BookCatalog.load()
        let seed = try XCTUnwrap(catalog.first { $0.id == "frankenstein" })

        for intent in RecommendationIntent.allCases {
            let recommendations = RecommendationEngine().recommendations(
                for: seed,
                from: catalog,
                intent: intent
            )

            XCTAssertEqual(recommendations.count, 3, "Expected results for \(intent.title)")
            XCTAssertEqual(Set(recommendations.map(\.book.id)).count, recommendations.count)
            XCTAssertFalse(recommendations.contains { $0.book.id == seed.id })
        }
    }

    func testLimitIsRespected() {
        let seed = makeBook(id: "seed", title: "Seed", genre: "Classic", rating: 4, keywords: ["society"])
        let catalog = [
            seed,
            makeBook(id: "one", title: "One", genre: "Classic", rating: 4, keywords: ["society"]),
            makeBook(id: "two", title: "Two", genre: "Classic", rating: 4, keywords: ["society"])
        ]

        let recommendations = RecommendationEngine().recommendations(for: seed, from: catalog, limit: 1)

        XCTAssertEqual(recommendations.count, 1)
    }

    private func makeBook(
        id: String,
        title: String,
        genre: String,
        rating: Double,
        summary: String = "",
        keywords: [String]
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: "Author \(id)",
            genre: genre,
            rating: rating,
            summary: summary,
            keywords: keywords
        )
    }
}
