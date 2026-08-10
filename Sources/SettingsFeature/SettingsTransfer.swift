import FileAccess
import Foundation
import PanelFeature

public struct SettingsTransferSettings: Codable, Equatable, Sendable {
    public var panelPlacement: PanelPlacementPreference
    public var shortcut: ShortcutBinding
    public var launchAtLogin: Bool
    public var showHiddenFiles: Bool
    public var visibleDetailColumns: [FileDetailColumn]
    public var defaultLocationPath: String?

    public init(settings: AppSettings) {
        self.panelPlacement = settings.panelPlacement
        self.shortcut = settings.shortcut
        self.launchAtLogin = settings.launchAtLogin
        self.showHiddenFiles = settings.showHiddenFiles
        self.visibleDetailColumns = settings.visibleDetailColumns
        self.defaultLocationPath = settings.defaultLocationPath
    }

    public var appSettings: AppSettings {
        AppSettings(
            panelPlacement: panelPlacement,
            shortcut: shortcut,
            launchAtLogin: launchAtLogin,
            showHiddenFiles: showHiddenFiles,
            visibleDetailColumns: visibleDetailColumns,
            defaultLocationPath: defaultLocationPath
        )
    }
}

public struct TransferSavedLocation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var bookmark: PersistedBookmark
    public var sortOrder: Int
    public var lastKnownExternalKind: SavedLocation.ExternalKind?
    public var groupID: UUID?

    public init(location: SavedLocation) {
        self.id = location.id
        self.displayName = location.displayName
        self.bookmark = location.bookmark
        self.sortOrder = location.sortOrder
        self.lastKnownExternalKind = location.lastKnownExternalKind
        self.groupID = location.groupID
    }

    public func savedLocation(availability: SavedLocation.Availability) -> SavedLocation {
        SavedLocation(
            id: id,
            displayName: displayName,
            bookmark: bookmark,
            sortOrder: sortOrder,
            availability: availability,
            lastKnownExternalKind: lastKnownExternalKind,
            groupID: groupID
        )
    }
}

public struct SettingsTransferManifest: Codable, Equatable, Sendable {
    public static let formatIdentifier = "io.github.achieve0410.PathShelf.settings-transfer"
    public static let currentSchemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var producerVersion: String
    public var settings: SettingsTransferSettings
    public var favoriteGroups: [FavoriteGroup]
    public var savedLocations: [TransferSavedLocation]

    public init(
        format: String = Self.formatIdentifier,
        schemaVersion: Int = Self.currentSchemaVersion,
        producerVersion: String,
        settings: SettingsTransferSettings,
        favoriteGroups: [FavoriteGroup],
        savedLocations: [TransferSavedLocation]
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.producerVersion = producerVersion
        self.settings = settings
        self.favoriteGroups = favoriteGroups
        self.savedLocations = savedLocations
    }
}

public enum SettingsTransferError: Error, Equatable, Sendable {
    case invalidDocument
    case documentTooLarge
    case resourceLimitExceeded
    case unsupportedFormat
    case unsupportedVersion(Int)
    case invalidProducerVersion
    case emptyGroupName(UUID)
    case duplicateGroupID(UUID)
    case duplicateLocationID(UUID)
    case duplicatePath(String)
    case danglingGroupID(UUID)
    case invalidPath(String)
    case invalidSortOrder(Int)
    case duplicateGroupSortOrder(Int)
    case duplicateLocationSortOrder(Int, UUID?)
}

public struct SettingsTransferCodec: Sendable {
    public static let maximumDocumentByteCount = 16 * 1_024 * 1_024

    private static let maximumFavoriteGroupCount = 256
    private static let maximumSavedLocationCount = 1_024
    private static let maximumTextByteCount = 4_096
    private static let maximumBookmarkByteCount = 1_024 * 1_024
    private static let maximumTotalBookmarkByteCount = 8 * 1_024 * 1_024

    private struct Header: Decodable {
        var format: String
        var schemaVersion: Int
    }

    public init() {}

    public func makeManifest(
        settings: AppSettings,
        favoriteGroups: [FavoriteGroup],
        savedLocations: [SavedLocation],
        producerVersion: String
    ) throws -> SettingsTransferManifest {
        try validatedAndSorted(
            SettingsTransferManifest(
            producerVersion: producerVersion,
            settings: SettingsTransferSettings(settings: settings),
            favoriteGroups: favoriteGroups,
            savedLocations: savedLocations.map(TransferSavedLocation.init(location:))
            )
        )
    }

    public func encode(_ manifest: SettingsTransferManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(validatedAndSorted(manifest))
    }

    public func decode(_ data: Data) throws -> SettingsTransferManifest {
        guard data.count <= Self.maximumDocumentByteCount else {
            throw SettingsTransferError.documentTooLarge
        }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw SettingsTransferError.invalidDocument
        }
        guard header.format == SettingsTransferManifest.formatIdentifier else {
            throw SettingsTransferError.unsupportedFormat
        }
        guard header.schemaVersion == SettingsTransferManifest.currentSchemaVersion else {
            throw SettingsTransferError.unsupportedVersion(header.schemaVersion)
        }
        let manifest: SettingsTransferManifest
        do {
            manifest = try decoder.decode(SettingsTransferManifest.self, from: data)
        } catch {
            throw SettingsTransferError.invalidDocument
        }
        return try validatedAndSorted(manifest)
    }

    private func validatedAndSorted(
        _ manifest: SettingsTransferManifest
    ) throws -> SettingsTransferManifest {
        guard manifest.favoriteGroups.count <= Self.maximumFavoriteGroupCount,
              manifest.savedLocations.count <= Self.maximumSavedLocationCount else {
            throw SettingsTransferError.resourceLimitExceeded
        }
        guard manifest.format == SettingsTransferManifest.formatIdentifier else {
            throw SettingsTransferError.unsupportedFormat
        }
        guard manifest.schemaVersion == SettingsTransferManifest.currentSchemaVersion else {
            throw SettingsTransferError.unsupportedVersion(manifest.schemaVersion)
        }
        guard manifest.producerVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SettingsTransferError.invalidProducerVersion
        }
        guard isBoundedText(manifest.producerVersion),
              manifest.settings.defaultLocationPath.map(isBoundedText) ?? true else {
            throw SettingsTransferError.resourceLimitExceeded
        }
        if let defaultPath = manifest.settings.defaultLocationPath,
           normalizedPath(defaultPath) == nil {
            throw SettingsTransferError.invalidPath(defaultPath)
        }

        var groupIDs = Set<UUID>()
        var groupSortOrders = Set<Int>()
        for group in manifest.favoriteGroups {
            guard isBoundedText(group.name),
                  group.iconName.map(isBoundedText) ?? true else {
                throw SettingsTransferError.resourceLimitExceeded
            }
            guard group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw SettingsTransferError.emptyGroupName(group.id)
            }
            guard groupIDs.insert(group.id).inserted else {
                throw SettingsTransferError.duplicateGroupID(group.id)
            }
            guard group.sortOrder >= 0 else {
                throw SettingsTransferError.invalidSortOrder(group.sortOrder)
            }
            guard groupSortOrders.insert(group.sortOrder).inserted else {
                throw SettingsTransferError.duplicateGroupSortOrder(group.sortOrder)
            }
        }

        var locationIDs = Set<UUID>()
        var paths = Set<String>()
        var locationSortOrders: [UUID?: Set<Int>] = [:]
        var totalBookmarkByteCount = 0
        for location in manifest.savedLocations {
            guard isBoundedText(location.displayName),
                  isBoundedText(location.bookmark.originalPath),
                  location.bookmark.data.count <= Self.maximumBookmarkByteCount else {
                throw SettingsTransferError.resourceLimitExceeded
            }
            totalBookmarkByteCount += location.bookmark.data.count
            guard totalBookmarkByteCount <= Self.maximumTotalBookmarkByteCount else {
                throw SettingsTransferError.resourceLimitExceeded
            }
            guard locationIDs.insert(location.id).inserted else {
                throw SettingsTransferError.duplicateLocationID(location.id)
            }
            guard let path = normalizedPath(location.bookmark.originalPath) else {
                throw SettingsTransferError.invalidPath(location.bookmark.originalPath)
            }
            guard paths.insert(path).inserted else {
                throw SettingsTransferError.duplicatePath(path)
            }
            if let groupID = location.groupID, groupIDs.contains(groupID) == false {
                throw SettingsTransferError.danglingGroupID(groupID)
            }
            guard location.sortOrder >= 0 else {
                throw SettingsTransferError.invalidSortOrder(location.sortOrder)
            }
            guard locationSortOrders[location.groupID, default: []]
                .insert(location.sortOrder).inserted else {
                throw SettingsTransferError.duplicateLocationSortOrder(
                    location.sortOrder,
                    location.groupID
                )
            }
        }

        var sorted = manifest
        sorted.favoriteGroups.sort {
            ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString)
        }
        sorted.savedLocations.sort {
            ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString)
        }
        return sorted
    }

    private func isBoundedText(_ text: String) -> Bool {
        text.utf8.count <= Self.maximumTextByteCount
    }

    private func normalizedPath(_ path: String) -> String? {
        guard path.isEmpty == false, path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
