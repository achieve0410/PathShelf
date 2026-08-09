import AppKit
import Foundation
@preconcurrency import QuickLookThumbnailing

public struct ThumbnailRequest: Equatable, Sendable {
    public var id: UUID
    public var url: URL
    public var size: CGSize
    public var scale: CGFloat

    public init(
        id: UUID = UUID(),
        url: URL,
        size: CGSize = CGSize(width: 96, height: 96),
        scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.scale = scale
    }
}

public struct ThumbnailResult: Sendable {
    public var requestID: UUID
    public var image: NSImage

    public init(requestID: UUID, image: NSImage) {
        self.requestID = requestID
        self.image = image
    }
}

public enum ThumbnailError: Error, Equatable, Sendable {
    case canceled(UUID)
    case generationFailed(UUID, String)
}

public struct ThumbnailServiceSnapshot: Equatable, Sendable {
    public var activeRequestCount: Int
    public var startedCount: Int
    public var canceledCount: Int
    public var completedCount: Int

    public init(
        activeRequestCount: Int,
        startedCount: Int,
        canceledCount: Int,
        completedCount: Int
    ) {
        self.activeRequestCount = activeRequestCount
        self.startedCount = startedCount
        self.canceledCount = canceledCount
        self.completedCount = completedCount
    }
}

public final class ThumbnailService: @unchecked Sendable {
    public typealias Generate = @Sendable (
        ThumbnailRequest,
        @escaping @Sendable (Result<ThumbnailResult, Error>) -> Void
    ) -> any CancellableThumbnailRequest

    private let generate: Generate
    private let lock = NSLock()
    private var active: [UUID: ThumbnailRequestState] = [:]
    private var startedCount = 0
    private var canceledCount = 0
    private var completedCount = 0

    public init(generate: @escaping Generate = ThumbnailService.liveGenerator) {
        self.generate = generate
    }

    public func thumbnail(for request: ThumbnailRequest) async throws -> ThumbnailResult {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = ThumbnailRequestState { result in
                    continuation.resume(with: result)
                }

                lock.lock()
                startedCount += 1
                active[request.id] = state
                lock.unlock()

                let cancellable = generate(request) { [weak self] result in
                    self?.complete(requestID: request.id, result: result)
                }

                let shouldCancelHandle: Bool
                lock.lock()
                if active[request.id] === state && state.terminal == nil {
                    state.handle = cancellable
                    shouldCancelHandle = false
                } else {
                    shouldCancelHandle = state.terminal == .canceled
                }
                lock.unlock()

                if shouldCancelHandle {
                    cancellable.cancel()
                }
            }
        } onCancel: {
            cancel(request.id)
        }
    }

    public func cancel(_ requestID: UUID) {
        let cancellable: (any CancellableThumbnailRequest)?
        let resume: (@Sendable (Result<ThumbnailResult, Error>) -> Void)?
        lock.lock()
        if let state = active.removeValue(forKey: requestID),
           state.terminal == nil {
            state.terminal = .canceled
            cancellable = state.handle
            resume = state.resume
            canceledCount += 1
        } else {
            cancellable = nil
            resume = nil
        }
        lock.unlock()
        cancellable?.cancel()
        resume?(.failure(ThumbnailError.canceled(requestID)))
    }

    public func cancelAll() {
        let cancellables: [any CancellableThumbnailRequest]
        let resumptions: [(UUID, @Sendable (Result<ThumbnailResult, Error>) -> Void)]
        lock.lock()
        let states = active
        cancellables = states.values.compactMap(\.handle)
        resumptions = states.compactMap { id, state in
            guard state.terminal == nil else {
                return nil
            }
            state.terminal = .canceled
            return (id, state.resume)
        }
        canceledCount += resumptions.count
        active.removeAll()
        lock.unlock()
        cancellables.forEach { $0.cancel() }
        resumptions.forEach { id, resume in
            resume(.failure(ThumbnailError.canceled(id)))
        }
    }

    public var snapshot: ThumbnailServiceSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ThumbnailServiceSnapshot(
            activeRequestCount: active.count,
            startedCount: startedCount,
            canceledCount: canceledCount,
            completedCount: completedCount
        )
    }

    private func complete(
        requestID: UUID,
        result: Result<ThumbnailResult, Error>
    ) {
        let resume: (@Sendable (Result<ThumbnailResult, Error>) -> Void)?
        lock.lock()
        if let state = active.removeValue(forKey: requestID),
           state.terminal == nil {
            state.terminal = .completed
            resume = state.resume
            completedCount += 1
        } else {
            resume = nil
        }
        lock.unlock()
        resume?(result)
    }

    public static func liveGenerator(
        request: ThumbnailRequest,
        completion: @escaping @Sendable (Result<ThumbnailResult, Error>) -> Void
    ) -> any CancellableThumbnailRequest {
        let qlRequest = QLThumbnailGenerator.Request(
            fileAt: request.url,
            size: request.size,
            scale: request.scale,
            representationTypes: .thumbnail
        )
        let handle = QuickLookThumbnailHandle(request: qlRequest)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: qlRequest) { representation, error in
            if let error {
                completion(.failure(ThumbnailError.generationFailed(request.id, String(describing: error))))
            } else if let representation {
                completion(.success(ThumbnailResult(requestID: request.id, image: representation.nsImage)))
            } else {
                completion(.failure(ThumbnailError.generationFailed(request.id, "No representation returned")))
            }
        }
        return handle
    }
}

private final class ThumbnailRequestState: @unchecked Sendable {
    enum Terminal {
        case completed
        case canceled
    }

    var handle: (any CancellableThumbnailRequest)?
    var terminal: Terminal?
    let resume: @Sendable (Result<ThumbnailResult, Error>) -> Void

    init(resume: @escaping @Sendable (Result<ThumbnailResult, Error>) -> Void) {
        self.resume = resume
    }
}

public protocol CancellableThumbnailRequest: Sendable {
    func cancel()
}

private final class QuickLookThumbnailHandle: CancellableThumbnailRequest, @unchecked Sendable {
    let request: QLThumbnailGenerator.Request

    init(request: QLThumbnailGenerator.Request) {
        self.request = request
    }

    func cancel() {
        QLThumbnailGenerator.shared.cancel(request)
    }
}
