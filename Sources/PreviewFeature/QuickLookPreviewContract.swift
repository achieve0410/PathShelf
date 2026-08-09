import Foundation

public struct PreviewItem: Equatable, Sendable {
    public var url: URL
    public var displayName: String

    public init(url: URL, displayName: String? = nil) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
    }
}

public enum PreviewState: Equatable, Sendable {
    case idle
    case presenting(PreviewItem)
    case closed
}

@MainActor
public final class QuickLookPreviewController {
    public private(set) var state: PreviewState = .idle
    public private(set) var presentedItems: [PreviewItem] = []

    public init() {}

    public func present(_ item: PreviewItem) {
        presentedItems = [item]
        state = .presenting(item)
    }

    public func close() {
        state = .closed
        presentedItems.removeAll()
    }
}
