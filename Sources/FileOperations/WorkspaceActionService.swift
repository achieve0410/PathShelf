import AppKit
import Foundation

public struct WorkspaceApplication: Equatable, Sendable {
    public var name: String
    public var bundleIdentifier: String?
    public var url: URL

    public init(name: String, bundleIdentifier: String?, url: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
    }
}

public enum WorkspaceAction: Equatable, Sendable {
    case openDefault(URL)
    case revealInFinder(URL)
    case openWith(item: URL, application: URL)
}

public enum WorkspaceActionError: Error, Equatable, Sendable, CustomStringConvertible {
    case openFailed(URL)
    case revealFailed(URL)
    case applicationOpenFailed(item: URL, application: URL, message: String)

    public var description: String {
        switch self {
        case .openFailed(let url):
            return "Could not open \(url.path) with the default application."
        case .revealFailed(let url):
            return "Could not reveal \(url.path) in Finder."
        case .applicationOpenFailed(let item, let application, let message):
            return "Could not open \(item.path) with \(application.path): \(message)"
        }
    }
}

public struct WorkspaceActionAdapter: Sendable {
    public var open: @Sendable (URL) -> Bool
    public var applications: @Sendable (URL) -> [WorkspaceApplication]
    public var openWithApplication: @Sendable (
        URL,
        URL,
        @escaping @Sendable (Error?) -> Void
    ) -> Void
    public var reveal: @Sendable (URL) -> Bool

    public init(
        open: @escaping @Sendable (URL) -> Bool,
        applications: @escaping @Sendable (URL) -> [WorkspaceApplication],
        openWithApplication: @escaping @Sendable (
            URL,
            URL,
            @escaping @Sendable (Error?) -> Void
        ) -> Void,
        reveal: @escaping @Sendable (URL) -> Bool
    ) {
        self.open = open
        self.applications = applications
        self.openWithApplication = openWithApplication
        self.reveal = reveal
    }

    @MainActor
    public static let live = WorkspaceActionAdapter(
        open: { url in
            NSWorkspace.shared.open(url)
        },
        applications: { url in
            NSWorkspace.shared.urlsForApplications(toOpen: url).map { appURL in
                WorkspaceApplication(
                    name: appURL.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: Bundle(url: appURL)?.bundleIdentifier,
                    url: appURL
                )
            }
        },
        openWithApplication: { itemURL, applicationURL, completion in
            let configuration = NSWorkspace.OpenConfiguration()
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    [itemURL],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { _, error in
                    completion(error)
                }
            }
        },
        reveal: { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        }
    )
}

public struct WorkspaceActionService: Sendable {
    private let adapter: WorkspaceActionAdapter

    public init(adapter: WorkspaceActionAdapter) {
        self.adapter = adapter
    }

    @MainActor
    public init() {
        self.adapter = .live
    }

    @MainActor
    public func openDefault(_ url: URL) throws {
        guard adapter.open(url) else {
            throw WorkspaceActionError.openFailed(url)
        }
    }

    @MainActor
    public func compatibleApplications(for url: URL) -> [WorkspaceApplication] {
        adapter.applications(url)
    }

    @MainActor
    public func open(_ itemURL: URL, with applicationURL: URL) async throws {
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            adapter.openWithApplication(itemURL, applicationURL) { error in
                if let error {
                    continuation.resume(
                        throwing: WorkspaceActionError.applicationOpenFailed(
                            item: itemURL,
                            application: applicationURL,
                            message: String(describing: error)
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    public func revealInFinder(_ url: URL) throws {
        guard adapter.reveal(url) else {
            throw WorkspaceActionError.revealFailed(url)
        }
    }
}
