import Foundation

enum BookCatalog {
    static func load(from bundle: Bundle = .main) -> [Book] {
        guard let url = bundle.url(forResource: "BookCatalog", withExtension: "json") else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Book].self, from: data)
        } catch {
            assertionFailure("Unable to load BookCatalog.json: \(error)")
            return []
        }
    }
}

