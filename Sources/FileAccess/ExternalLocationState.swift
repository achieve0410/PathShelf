import Foundation

public enum UbiquitousDownloadState: String, Equatable, Sendable {
    case current
    case downloaded
    case notDownloaded
    case unknown
}

public struct ExternalLocationMetadata: Equatable, Sendable {
    public var exists: Bool
    public var isRemovable: Bool
    public var isLocalVolume: Bool
    public var isUbiquitousItem: Bool
    public var ubiquitousDownloadState: UbiquitousDownloadState

    public init(
        exists: Bool,
        isRemovable: Bool = false,
        isLocalVolume: Bool = true,
        isUbiquitousItem: Bool = false,
        ubiquitousDownloadState: UbiquitousDownloadState = .unknown
    ) {
        self.exists = exists
        self.isRemovable = isRemovable
        self.isLocalVolume = isLocalVolume
        self.isUbiquitousItem = isUbiquitousItem
        self.ubiquitousDownloadState = ubiquitousDownloadState
    }

    public var isICloudPlaceholder: Bool {
        isUbiquitousItem && ubiquitousDownloadState != .current && ubiquitousDownloadState != .downloaded
    }

    public var externalKind: SavedLocation.ExternalKind {
        if isUbiquitousItem {
            return .iCloud
        }
        if isRemovable {
            return .removable
        }
        if isLocalVolume == false {
            return .network
        }
        return .local
    }
}

public struct ExternalLocationProbe: Sendable {
    private let metadataClosure: @Sendable (URL) -> ExternalLocationMetadata

    public init(metadata: @escaping @Sendable (URL) -> ExternalLocationMetadata) {
        self.metadataClosure = metadata
    }

    public func metadata(for url: URL) -> ExternalLocationMetadata {
        metadataClosure(url)
    }

    public static let live = ExternalLocationProbe { url in
        let keys: Set<URLResourceKey> = [
            .volumeIsRemovableKey,
            .volumeIsLocalKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let status = values?.ubiquitousItemDownloadingStatus
        let mappedStatus: UbiquitousDownloadState
        switch status {
        case .current:
            mappedStatus = .current
        case .downloaded:
            mappedStatus = .downloaded
        case .notDownloaded:
            mappedStatus = .notDownloaded
        default:
            mappedStatus = .unknown
        }
        return ExternalLocationMetadata(
            exists: FileManager.default.fileExists(atPath: url.path),
            isRemovable: values?.volumeIsRemovable == true,
            isLocalVolume: values?.volumeIsLocal != false,
            isUbiquitousItem: values?.isUbiquitousItem == true,
            ubiquitousDownloadState: mappedStatus
        )
    }
}

public enum ExternalLocationStateResolver {
    public static func availability(
        current: SavedLocation.Availability,
        resolution: BookmarkResolution,
        metadata: ExternalLocationMetadata?,
        lastKnownExternalKind: SavedLocation.ExternalKind?,
        markRecovered: Bool
    ) -> SavedLocation.Availability {
        guard resolution.availability == .available, let metadata else {
            switch resolution.availability {
            case .staleBookmark, .permissionDenied:
                return resolution.availability
            default:
                if lastKnownExternalKind == .removable {
                    return .disconnected
                }
                if lastKnownExternalKind == .network {
                    return .networkUnavailable
                }
                if current == .disconnected {
                    return .disconnected
                }
                return .unavailable
            }
        }

        guard metadata.exists else {
            if metadata.isRemovable {
                return .disconnected
            }
            if metadata.isLocalVolume == false {
                return .networkUnavailable
            }
            return .unavailable
        }

        if metadata.isICloudPlaceholder {
            return .iCloudPlaceholder
        }

        if markRecovered && current != .available {
            return .recovered
        }
        return .available
    }

    public static func isUsable(_ availability: SavedLocation.Availability) -> Bool {
        switch availability {
        case .available, .recovered, .iCloudPlaceholder:
            return true
        case .unavailable, .disconnected, .networkUnavailable, .staleBookmark, .permissionDenied:
            return false
        }
    }
}
