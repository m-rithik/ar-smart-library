import Combine
import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case wantToRead
    case reading
    case finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wantToRead:
            return "Want to read"
        case .reading:
            return "Reading"
        case .finished:
            return "Finished"
        }
    }

    var systemImage: String {
        switch self {
        case .wantToRead:
            return "bookmark"
        case .reading:
            return "book"
        case .finished:
            return "checkmark.circle"
        }
    }
}

@MainActor
final class ReadingListStore: ObservableObject {
    @Published private(set) var statuses: [String: ReadingStatus]

    private let defaults: UserDefaults
    private static let storageKey = "reading-list-statuses-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        statuses = (defaults.dictionary(forKey: Self.storageKey) ?? [:]).compactMapValues { value in
            guard let rawValue = value as? String else { return nil }
            return ReadingStatus(rawValue: rawValue)
        }
    }

    func status(for bookID: String) -> ReadingStatus? {
        statuses[bookID]
    }

    func setStatus(_ status: ReadingStatus?, for bookID: String) {
        guard statuses[bookID] != status else { return }
        statuses[bookID] = status
        if statuses.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(statuses.mapValues(\.rawValue), forKey: Self.storageKey)
        }
    }
}
