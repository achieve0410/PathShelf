import Foundation

public struct SavedLocation: Codable, Equatable, Identifiable, Sendable {
    public enum ExternalKind: String, Codable, Sendable {
        case local
        case removable
        case network
        case iCloud
    }

    public enum Availability: String, Codable, Sendable {
        case available
        case unavailable
        case iCloudPlaceholder
        case disconnected
        case networkUnavailable
        case staleBookmark
        case permissionDenied
        case recovered
    }

    public var id: UUID
    public var displayName: String
    public var bookmark: PersistedBookmark
    public var sortOrder: Int
    public var availability: Availability
    public var lastKnownExternalKind: ExternalKind?
    public var groupID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case bookmark
        case sortOrder
        case availability
        case lastKnownExternalKind
        case groupID
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        bookmark: PersistedBookmark,
        sortOrder: Int,
        availability: Availability = .available,
        lastKnownExternalKind: ExternalKind? = nil,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
        self.sortOrder = sortOrder
        self.availability = availability
        self.lastKnownExternalKind = lastKnownExternalKind
        self.groupID = groupID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.bookmark = try container.decode(PersistedBookmark.self, forKey: .bookmark)
        self.sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        self.availability = try container.decode(Availability.self, forKey: .availability)
        self.lastKnownExternalKind = try container.decodeIfPresent(
            ExternalKind.self,
            forKey: .lastKnownExternalKind
        )
        self.groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
    }
}

public struct FavoriteGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var iconName: String?

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        iconName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.iconName = iconName
    }
}

public struct PersistedBookmark: Codable, Equatable, Sendable {
    public var data: Data
    public var originalPath: String
    public var isSecurityScoped: Bool

    public init(data: Data, originalPath: String, isSecurityScoped: Bool) {
        self.data = data
        self.originalPath = originalPath
        self.isSecurityScoped = isSecurityScoped
    }
}
