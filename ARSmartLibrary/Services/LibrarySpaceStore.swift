import Foundation

struct SavedLibrarySpace: Codable, Equatable {
    let version: Int
    let space: LibrarySpace
    let worldMapData: Data
    let localizationImageData: Data?

    init(space: LibrarySpace, worldMapData: Data, localizationImageData: Data? = nil) {
        version = 1
        self.space = space
        self.worldMapData = worldMapData
        self.localizationImageData = localizationImageData
    }
}

struct LibrarySpaceStore {
    let url: URL
    private var catalogBookIDs: Set<String>?

    init(url: URL? = nil, catalogBookIDs: Set<String>? = nil) {
        self.url = url ?? URL.applicationSupportDirectory
            .appendingPathComponent("ARSmartLibrary", isDirectory: true)
            .appendingPathComponent("library-space.json")
        self.catalogBookIDs = catalogBookIDs
    }

    mutating func updateCatalogBookIDs(_ ids: Set<String>) {
        catalogBookIDs = ids
    }

    func load() throws -> SavedLibrarySpace? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let saved = try JSONDecoder().decode(SavedLibrarySpace.self, from: Data(contentsOf: url))
        guard saved.version == 1 else { throw LibrarySpaceError.unsupportedVersion }
        try saved.space.validate(catalogBookIDs: catalogBookIDs)
        guard !saved.worldMapData.isEmpty else { throw LibrarySpaceError.missingWorldMap }
        return saved
    }

    func save(space: LibrarySpace, worldMapData: Data, localizationImageData: Data? = nil) throws {
        try space.validate(catalogBookIDs: catalogBookIDs)
        guard !worldMapData.isEmpty else { throw LibrarySpaceError.missingWorldMap }
        let data = try JSONEncoder().encode(SavedLibrarySpace(
            space: space,
            worldMapData: worldMapData,
            localizationImageData: localizationImageData
        ))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Keep shelf coordinates and their AR world map in a single atomic replacement.
        try data.write(to: url, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.removeItem(at: url)
    }
}
