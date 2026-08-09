import Foundation

public enum BookmarkAccessError: Error, Equatable, Sendable {
    case staleBookmark(originalPath: String)
    case permissionDenied(originalPath: String)
    case invalidBookmark(originalPath: String)
}

public struct BookmarkResolution: Sendable {
    public var scopedURL: SecurityScopedURL?
    public var originalPath: String
    public var isStale: Bool
    public var availability: SavedLocation.Availability
    public var error: BookmarkAccessError?

    public init(
        scopedURL: SecurityScopedURL?,
        originalPath: String,
        isStale: Bool,
        availability: SavedLocation.Availability,
        error: BookmarkAccessError?
    ) {
        self.scopedURL = scopedURL
        self.originalPath = originalPath
        self.isStale = isStale
        self.availability = availability
        self.error = error
    }
}

public final class SecurityScopedURL: @unchecked Sendable {
    public let url: URL

    private let shouldStopAccessing: Bool
    private let lock = NSLock()
    private var isClosed = false

    init(url: URL, shouldStopAccessing: Bool) {
        self.url = url
        self.shouldStopAccessing = shouldStopAccessing
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        let shouldClose = shouldStopAccessing && !isClosed
        if shouldClose {
            isClosed = true
        }
        lock.unlock()

        if shouldClose {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

public struct SecurityScopedBookmarkService: Sendable {
    private let resolveBookmark: @Sendable (PersistedBookmark, inout Bool) throws -> URL
    private let startAccessing: @Sendable (URL) -> Bool
    private let stopAccessing: @Sendable (URL) -> Void
    private let fileExists: @Sendable (String) -> Bool

    public init() {
        self.init(
            resolveBookmark: { bookmark, isStale in
                try URL(
                    resolvingBookmarkData: bookmark.data,
                    options: bookmark.isSecurityScoped ? [.withSecurityScope] : [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            },
            startAccessing: { url in
                url.startAccessingSecurityScopedResource()
            },
            stopAccessing: { url in
                url.stopAccessingSecurityScopedResource()
            },
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            }
        )
    }

    public init(
        resolveBookmark: @escaping @Sendable (PersistedBookmark, inout Bool) throws -> URL,
        startAccessing: @escaping @Sendable (URL) -> Bool,
        stopAccessing: @escaping @Sendable (URL) -> Void,
        fileExists: @escaping @Sendable (String) -> Bool
    ) {
        self.resolveBookmark = resolveBookmark
        self.startAccessing = startAccessing
        self.stopAccessing = stopAccessing
        self.fileExists = fileExists
    }

    public func makeBookmark(for url: URL) throws -> PersistedBookmark {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return PersistedBookmark(
            data: data,
            originalPath: url.path,
            isSecurityScoped: true
        )
    }

    public func resolve(_ bookmark: PersistedBookmark) -> BookmarkResolution {
        var isStale = false
        let resolvedURL: URL

        do {
            resolvedURL = try resolveBookmark(bookmark, &isStale)
        } catch {
            return BookmarkResolution(
                scopedURL: nil,
                originalPath: bookmark.originalPath,
                isStale: false,
                availability: .unavailable,
                error: .invalidBookmark(originalPath: bookmark.originalPath)
            )
        }

        if isStale {
            return BookmarkResolution(
                scopedURL: nil,
                originalPath: bookmark.originalPath,
                isStale: true,
                availability: .staleBookmark,
                error: .staleBookmark(originalPath: bookmark.originalPath)
            )
        }

        let didStartAccess = bookmark.isSecurityScoped
            ? startAccessing(resolvedURL)
            : false
        let exists = fileExists(resolvedURL.path)

        guard exists else {
            if didStartAccess {
                stopAccessing(resolvedURL)
            }
            return BookmarkResolution(
                scopedURL: nil,
                originalPath: bookmark.originalPath,
                isStale: false,
                availability: .unavailable,
                error: .invalidBookmark(originalPath: bookmark.originalPath)
            )
        }

        if bookmark.isSecurityScoped && !didStartAccess {
            return BookmarkResolution(
                scopedURL: nil,
                originalPath: bookmark.originalPath,
                isStale: false,
                availability: .permissionDenied,
                error: .permissionDenied(originalPath: bookmark.originalPath)
            )
        }

        return BookmarkResolution(
            scopedURL: SecurityScopedURL(url: resolvedURL, shouldStopAccessing: didStartAccess),
            originalPath: bookmark.originalPath,
            isStale: false,
            availability: .available,
            error: nil
        )
    }
}
