import Foundation
import Darwin

public struct DirectoryEnumerationResult: Sendable {
    public var items: [FileItem]
    public var completedOnMainThread: Bool

    public init(items: [FileItem], completedOnMainThread: Bool) {
        self.items = items
        self.completedOnMainThread = completedOnMainThread
    }
}

public struct DirectoryEnumerator: Sendable {
    public var showHiddenFiles: Bool

    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey
    ]

    public init(showHiddenFiles: Bool = false) {
        self.showHiddenFiles = showHiddenFiles
    }

    public func enumerate(_ directoryURL: URL) async throws -> DirectoryEnumerationResult {
        try Task.checkCancellation()
        let keys = resourceKeys
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: showHiddenFiles ? [] : [.skipsHiddenFiles]
            )
            try Task.checkCancellation()
            let mappedItems: [FileItem] = try urls.map { url in
                let values = try url.resourceValues(forKeys: keys)
                return FileItem(url: url, resourceValues: values)
            }
            try Task.checkCancellation()
            let items = mappedItems.sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            return DirectoryEnumerationResult(
                items: items,
                completedOnMainThread: pthread_main_np() != 0
            )
        }
        return try await task.value
    }
}
