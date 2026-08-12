import CoreServices
import Foundation

public enum DirectoryEventReason: String, Equatable, Sendable {
    case fsevents
    case injected
}

public struct DirectoryEvent: Equatable, Sendable {
    public var url: URL
    public var reason: DirectoryEventReason

    public init(url: URL, reason: DirectoryEventReason) {
        self.url = url
        self.reason = reason
    }
}

public protocol DirectoryEventStream: Sendable {
    func stop()
}

public struct DirectoryEventSource: Sendable {
    public typealias Start = @Sendable (
        _ root: URL,
        _ generation: Int,
        _ callback: @escaping @Sendable (Int, DirectoryEvent) -> Void
    ) -> any DirectoryEventStream

    private let startClosure: Start

    public init(start: @escaping Start) {
        self.startClosure = start
    }

    public func start(
        root: URL,
        generation: Int,
        callback: @escaping @Sendable (Int, DirectoryEvent) -> Void
    ) -> any DirectoryEventStream {
        startClosure(root, generation, callback)
    }

    public static let live = DirectoryEventSource { root, generation, callback in
        FSEventsDirectoryEventStream(root: root, generation: generation, callback: callback)
    }
}

public final class VisibleDirectoryMonitor: @unchecked Sendable {
    private let source: DirectoryEventSource
    private let diagnostics: LifecycleDiagnostics
    private let lock = NSLock()
    private var stream: (any DirectoryEventStream)?
    private var generation = 0
    private var isActive = false
    private var pendingEventKeys = Set<String>()

    public init(
        source: DirectoryEventSource = .live,
        diagnostics: LifecycleDiagnostics
    ) {
        self.source = source
        self.diagnostics = diagnostics
    }

    public func start(
        root: URL,
        onEvent: @escaping @MainActor @Sendable (Int, DirectoryEvent) -> Void
    ) {
        replaceRoot(root, onEvent: onEvent)
    }

    public func replaceRoot(
        _ root: URL,
        onEvent: @escaping @MainActor @Sendable (Int, DirectoryEvent) -> Void
    ) {
        let oldStream: (any DirectoryEventStream)?
        let nextGeneration: Int

        lock.lock()
        oldStream = stream
        if oldStream != nil {
            diagnostics.visibleDirectoryObserverStopped()
        }
        generation += 1
        nextGeneration = generation
        isActive = true
        pendingEventKeys.removeAll()
        lock.unlock()

        oldStream?.stop()

        let newStream = source.start(root: root, generation: nextGeneration) { [weak self] eventGeneration, event in
            self?.handle(eventGeneration: eventGeneration, event: event, onEvent: onEvent)
        }

        lock.lock()
        stream = newStream
        diagnostics.visibleDirectoryObserverStarted()
        lock.unlock()
    }

    public func stop() {
        let oldStream: (any DirectoryEventStream)?
        lock.lock()
        oldStream = stream
        stream = nil
        let wasActive = isActive
        isActive = false
        pendingEventKeys.removeAll()
        lock.unlock()

        if wasActive || oldStream != nil {
            diagnostics.visibleDirectoryObserverStopped()
        }
        oldStream?.stop()
    }

    public var currentGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func handle(
        eventGeneration: Int,
        event: DirectoryEvent,
        onEvent: @escaping @MainActor @Sendable (Int, DirectoryEvent) -> Void
    ) {
        let shouldDeliver: Bool
        lock.lock()
        let lifecycleActive = isActive
        let generationMatches = eventGeneration == generation
        diagnostics.callbackArrived(active: lifecycleActive, stale: lifecycleActive && generationMatches == false)
        if lifecycleActive && generationMatches {
            let key = "\(eventGeneration):\(event.url.path)"
            shouldDeliver = pendingEventKeys.insert(key).inserted
        } else {
            shouldDeliver = false
        }
        lock.unlock()

        guard shouldDeliver else {
            return
        }

        Task { @MainActor [weak self] in
            onEvent(eventGeneration, event)
            self?.finishDelivery(
                eventGeneration: eventGeneration,
                event: event
            )
        }
    }

    private func finishDelivery(
        eventGeneration: Int,
        event: DirectoryEvent
    ) {
        lock.lock()
        pendingEventKeys.remove("\(eventGeneration):\(event.url.path)")
        lock.unlock()
    }
}

private final class FSEventsDirectoryEventStream: DirectoryEventStream, @unchecked Sendable {
    private final class Context: @unchecked Sendable {
        let generation: Int
        let callback: @Sendable (Int, DirectoryEvent) -> Void

        init(generation: Int, callback: @escaping @Sendable (Int, DirectoryEvent) -> Void) {
            self.generation = generation
            self.callback = callback
        }
    }

    private let queue = DispatchQueue(label: "PathShelf.visible-directory-events")
    private var stream: FSEventStreamRef?
    private var contextPointer: UnsafeMutableRawPointer?
    private let lock = NSLock()
    private var isStopped = false

    init(
        root: URL,
        generation: Int,
        callback: @escaping @Sendable (Int, DirectoryEvent) -> Void
    ) {
        let context = Context(generation: generation, callback: callback)
        let pointer = Unmanaged.passRetained(context).toOpaque()
        contextPointer = pointer
        var streamContext = FSEventStreamContext(
            version: 0,
            info: pointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [root.path] as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, eventCount, eventPaths, _, _ in
                guard let info else {
                    return
                }
                let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                for index in 0..<eventCount {
                    let path = index < paths.count ? paths[index] : ""
                    context.callback(
                        context.generation,
                        DirectoryEvent(url: URL(fileURLWithPath: path), reason: .fsevents)
                    )
                }
            },
            &streamContext,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        stop()
    }

    func stop() {
        let streamToStop: FSEventStreamRef?
        let pointerToRelease: UnsafeMutableRawPointer?
        lock.lock()
        guard isStopped == false else {
            lock.unlock()
            return
        }
        isStopped = true
        streamToStop = stream
        pointerToRelease = contextPointer
        stream = nil
        contextPointer = nil
        lock.unlock()

        if let streamToStop {
            FSEventStreamStop(streamToStop)
            FSEventStreamInvalidate(streamToStop)
            FSEventStreamRelease(streamToStop)
        }
        if let pointerToRelease {
            Unmanaged<Context>.fromOpaque(pointerToRelease).release()
        }
    }
}
