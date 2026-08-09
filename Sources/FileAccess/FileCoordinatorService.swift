import Foundation
import Darwin

public struct CoordinatedReadResult: Sendable {
    public var data: Data
    public var completedOnMainThread: Bool

    public init(data: Data, completedOnMainThread: Bool) {
        self.data = data
        self.completedOnMainThread = completedOnMainThread
    }
}

public enum FileCoordinatorServiceError: Error, Equatable, Sendable {
    case accessorDidNotProduceResult
}

public struct FileCoordinatorService: Sendable {
    private let readCoordinator: @Sendable (URL) throws -> Data?

    public init() {
        self.init { url in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var result: Result<Data, Error>?

            coordinator.coordinate(
                readingItemAt: url,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                result = Result {
                    try Data(contentsOf: coordinatedURL)
                }
            }

            if let coordinationError {
                throw coordinationError
            }

            return try result?.get()
        }
    }

    public init(readCoordinator: @escaping @Sendable (URL) throws -> Data?) {
        self.readCoordinator = readCoordinator
    }

    public func coordinatedRead(at url: URL) async throws -> CoordinatedReadResult {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let data = try readCoordinator(url) else {
                throw FileCoordinatorServiceError.accessorDidNotProduceResult
            }
            try Task.checkCancellation()
            return CoordinatedReadResult(
                data: data,
                completedOnMainThread: pthread_main_np() != 0
            )
        }
        return try await task.value
    }
}
