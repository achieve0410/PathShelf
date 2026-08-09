import Foundation

public enum SettingsStoreError: Error, Equatable {
    case missingFile
}

public protocol SettingsPersisting: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

public final class SettingsStore: SettingsPersisting, @unchecked Sendable {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL) {
        self.storageURL = storageURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            throw SettingsStoreError.missingFile
        }

        let data = try Data(contentsOf: storageURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(settings)
        try data.write(to: storageURL, options: [.atomic])
    }
}
