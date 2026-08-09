import Foundation

public struct HomeDirectoryProvider: Sendable {
    public init() {}

    public var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}
