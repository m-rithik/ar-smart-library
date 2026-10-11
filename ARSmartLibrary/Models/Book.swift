import CoreGraphics
import Foundation

struct Book: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let author: String
    let genre: String
    let rating: Double
    let summary: String
    let keywords: [String]
}

struct BookMatch: Equatable {
    let book: Book
    let confidence: Double
    let titleOCRConfidence: Double
    let localizedTitleCoverage: Double
    let visionTargetPoint: CGPoint
    let evidence: String
}

struct BookRecommendation: Identifiable, Equatable {
    var id: String { book.id }

    let book: Book
    let score: Double
    let reason: String
}

enum RecommendationIntent: String, CaseIterable, Identifiable {
    case similar
    case explore
    case highlyRated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .similar:
            return "Similar"
        case .explore:
            return "Explore"
        case .highlyRated:
            return "Top rated"
        }
    }
}

enum LibraryUseCase: Equatable {
    case identify
    case find(target: Book)
    case compare(seed: Book)
}

struct BookComparison: Equatable {
    let first: Book
    let second: Book
    let similarity: Double
    let sharedThemes: [String]
}

enum ScanPolicy: Equatable {
    case exact
    case region

    var title: String {
        switch self {
        case .exact:
            return "Exact match"
        case .region:
            return "Possible match"
        }
    }

    var systemImage: String {
        switch self {
        case .exact:
            return "scope"
        case .region:
            return "rectangle.dashed"
        }
    }
}
