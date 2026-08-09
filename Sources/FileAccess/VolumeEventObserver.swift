import AppKit
import Foundation

public enum VolumeEventKind: String, Equatable, Sendable {
    case mounted
    case unmounted
    case renamed
    case injected
}

public struct VolumeEvent: Equatable, Sendable {
    public var url: URL?
    public var kind: VolumeEventKind

    public init(url: URL?, kind: VolumeEventKind) {
        self.url = url
        self.kind = kind
    }
}

public protocol VolumeEventStream: Sendable {
    func stop()
}

public struct VolumeEventSource: Sendable {
    public typealias Start = @Sendable (
        _ callback: @escaping @Sendable (VolumeEvent) -> Void
    ) -> any VolumeEventStream

    private let startClosure: Start

    public init(start: @escaping Start) {
        self.startClosure = start
    }

    public func start(callback: @escaping @Sendable (VolumeEvent) -> Void) -> any VolumeEventStream {
        startClosure(callback)
    }

    public static let live = VolumeEventSource { callback in
        WorkspaceVolumeEventStream(callback: callback)
    }
}

public final class VolumeEventObserver: @unchecked Sendable {
    private let source: VolumeEventSource
    private let diagnostics: LifecycleDiagnostics
    private let lock = NSLock()
    private var stream: (any VolumeEventStream)?
    private var isActive = false

    public init(
        source: VolumeEventSource = .live,
        diagnostics: LifecycleDiagnostics
    ) {
        self.source = source
        self.diagnostics = diagnostics
    }

    public func start(onEvent: @escaping @MainActor @Sendable (VolumeEvent) -> Void) {
        stop()
        lock.lock()
        isActive = true
        lock.unlock()

        let newStream = source.start { [weak self] event in
            self?.handle(event: event, onEvent: onEvent)
        }

        lock.lock()
        stream = newStream
        diagnostics.volumeObserverStarted()
        lock.unlock()
    }

    public func stop() {
        let oldStream: (any VolumeEventStream)?
        lock.lock()
        oldStream = stream
        stream = nil
        let wasActive = isActive
        isActive = false
        lock.unlock()

        if wasActive || oldStream != nil {
            diagnostics.volumeObserverStopped()
        }
        oldStream?.stop()
    }

    private func handle(
        event: VolumeEvent,
        onEvent: @escaping @MainActor @Sendable (VolumeEvent) -> Void
    ) {
        lock.lock()
        let active = isActive
        diagnostics.callbackArrived(active: active)
        lock.unlock()

        guard active else {
            return
        }

        Task { @MainActor in
            onEvent(event)
        }
    }
}

private final class WorkspaceVolumeEventStream: NSObject, VolumeEventStream, @unchecked Sendable {
    private let callback: @Sendable (VolumeEvent) -> Void
    private var tokens: [NSObjectProtocol] = []
    private let lock = NSLock()
    private var isStopped = false

    init(callback: @escaping @Sendable (VolumeEvent) -> Void) {
        self.callback = callback
        super.init()

        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.callback(VolumeEvent(url: notification.volumeURL, kind: .mounted))
            },
            center.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.callback(VolumeEvent(url: notification.volumeURL, kind: .unmounted))
            },
            center.addObserver(
                forName: NSWorkspace.didRenameVolumeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.callback(VolumeEvent(url: notification.volumeURL, kind: .renamed))
            }
        ]
    }

    deinit {
        stop()
    }

    func stop() {
        let tokensToRemove: [NSObjectProtocol]
        lock.lock()
        guard isStopped == false else {
            lock.unlock()
            return
        }
        isStopped = true
        tokensToRemove = tokens
        tokens.removeAll()
        lock.unlock()

        let center = NSWorkspace.shared.notificationCenter
        tokensToRemove.forEach { center.removeObserver($0) }
    }
}

private extension Notification {
    var volumeURL: URL? {
        userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
    }
}
