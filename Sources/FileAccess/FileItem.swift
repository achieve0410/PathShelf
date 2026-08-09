import Foundation

public struct FileItem: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case directory
        case file
        case symbolicLink
        case other
    }

    public enum LocalAvailability: String, Equatable, Sendable {
        case local
        case downloadRequired
        case unknown
    }

    public var url: URL
    public var name: String
    public var kind: Kind
    public var byteSize: Int64?
    public var contentModificationDate: Date?
    public var creationDate: Date?
    public var isHidden: Bool
    public var localAvailability: LocalAvailability

    public init(
        url: URL,
        name: String,
        kind: Kind,
        byteSize: Int64?,
        contentModificationDate: Date?,
        creationDate: Date?,
        isHidden: Bool,
        localAvailability: LocalAvailability = .unknown
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.byteSize = byteSize
        self.contentModificationDate = contentModificationDate
        self.creationDate = creationDate
        self.isHidden = isHidden
        self.localAvailability = localAvailability
    }
}

extension FileItem {
    public enum LocalAvailabilityClassifier {
        public static func classify(
            isUbiquitousItem: Bool?,
            downloadingState: UbiquitousDownloadState
        ) -> LocalAvailability {
            guard isUbiquitousItem == true else {
                return .local
            }
            switch downloadingState {
            case .current, .downloaded:
                return .local
            case .notDownloaded:
                return .downloadRequired
            case .unknown:
                return .unknown
            }
        }
    }

    public static func localAvailability(resourceValues: URLResourceValues) -> LocalAvailability {
        let downloadingState: UbiquitousDownloadState
        switch resourceValues.ubiquitousItemDownloadingStatus {
        case .current:
            downloadingState = .current
        case .downloaded:
            downloadingState = .downloaded
        case .notDownloaded:
            downloadingState = .notDownloaded
        default:
            downloadingState = .unknown
        }
        return LocalAvailabilityClassifier.classify(
            isUbiquitousItem: resourceValues.isUbiquitousItem,
            downloadingState: downloadingState
        )
    }

    init(url: URL, resourceValues: URLResourceValues) {
        let kind: Kind
        if resourceValues.isSymbolicLink == true {
            kind = .symbolicLink
        } else if resourceValues.isDirectory == true {
            kind = .directory
        } else if resourceValues.isRegularFile == true {
            kind = .file
        } else {
            kind = .other
        }

        self.init(
            url: url,
            name: url.lastPathComponent,
            kind: kind,
            byteSize: resourceValues.fileSize.map(Int64.init),
            contentModificationDate: resourceValues.contentModificationDate,
            creationDate: resourceValues.creationDate,
            isHidden: resourceValues.isHidden == true,
            localAvailability: Self.localAvailability(resourceValues: resourceValues)
        )
    }
}
