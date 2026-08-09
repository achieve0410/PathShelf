import Foundation

public enum NavigationAccessPolicyError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedSavedLocation(String)

    public var description: String {
        switch self {
        case .unsupportedSavedLocation(let path):
            return "Saved location is outside the supported local home or external volume scope: \(path)"
        }
    }
}

public struct NavigationAccessPolicy: Sendable {
    public var homeRoot: URL
    public var userHomeRoot: URL

    public init(
        homeRoot: URL,
        userHomeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.homeRoot = homeRoot
        self.userHomeRoot = userHomeRoot
    }

    public func validateSavedLocation(_ url: URL) throws {
        let normalized = normalizedURL(url)
        guard isSupportedSavedLocation(normalized) else {
            throw NavigationAccessPolicyError.unsupportedSavedLocation(normalized.path)
        }
    }

    public func parentForUpNavigation(from currentURL: URL, scopedRoot: URL?) -> URL? {
        let current = normalizedURL(currentURL)
        let boundary = scopedRoot
            .map(normalizedURL)
            .flatMap { contains($0, current) ? $0 : nil } ?? normalizedURL(homeRoot)

        guard current.path != boundary.path else {
            return nil
        }

        let parent = normalizedURL(current.deletingLastPathComponent())
        guard parent.path != current.path, contains(boundary, parent) else {
            return nil
        }
        return parent
    }

    public func isInsideScopedRoot(_ url: URL, scopedRoot: URL) -> Bool {
        contains(normalizedURL(scopedRoot), normalizedURL(url))
    }

    private func isSupportedSavedLocation(_ url: URL) -> Bool {
        if contains(normalizedURL(homeRoot), url) || contains(normalizedURL(userHomeRoot), url) {
            return true
        }
        if url.path == "/" || Self.protectedSystemRoots.contains(where: { contains($0, url) }) {
            return false
        }
        if isExternalVolumeDescendant(url) {
            return true
        }
        return false
    }

    private func isExternalVolumeDescendant(_ url: URL) -> Bool {
        let components = url.pathComponents
        return components.count > 2 && components[0] == "/" && components[1] == "Volumes"
    }

    private static let protectedSystemRoots = [
        "/Applications",
        "/Library",
        "/System",
        "/bin",
        "/cores",
        "/dev",
        "/etc",
        "/opt",
        "/private",
        "/sbin",
        "/tmp",
        "/usr",
        "/var"
    ].map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }

    private func contains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else {
            return false
        }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private func normalizedURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }
}
