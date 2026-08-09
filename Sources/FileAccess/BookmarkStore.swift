import Foundation

public protocol BookmarkStore: Sendable {
    func loadSavedLocations() throws -> [SavedLocation]
    func saveSavedLocations(_ locations: [SavedLocation]) throws
}

public protocol FavoriteGroupStore: Sendable {
    func loadFavoriteGroups() throws -> [FavoriteGroup]
    func saveFavoriteGroups(_ groups: [FavoriteGroup]) throws
}

public final class JSONBookmarkStore: BookmarkStore, @unchecked Sendable {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL) {
        self.storageURL = storageURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func loadSavedLocations() throws -> [SavedLocation] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        return try decoder.decode([SavedLocation].self, from: data)
    }

    public func saveSavedLocations(_ locations: [SavedLocation]) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let orderedLocations = locations.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        let data = try encoder.encode(orderedLocations)
        try data.write(to: storageURL, options: [.atomic])
    }
}

public final class JSONFavoriteGroupStore: FavoriteGroupStore, @unchecked Sendable {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(storageURL: URL) {
        self.storageURL = storageURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadFavoriteGroups() throws -> [FavoriteGroup] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }
        return try decoder.decode(
            [FavoriteGroup].self,
            from: Data(contentsOf: storageURL)
        ).sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    public func saveFavoriteGroups(_ groups: [FavoriteGroup]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(groups.sorted { $0.sortOrder < $1.sortOrder })
        try data.write(to: storageURL, options: [.atomic])
    }
}
