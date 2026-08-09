import Foundation
import Darwin

public enum ConflictPolicy: String, Codable, Equatable, Sendable {
    case skip
    case keepBoth
    case replace
}

public enum FileOperationAction: String, Codable, Equatable, Sendable {
    case createFolder
    case rename
    case copy
    case move
    case trash
}

public enum FileOperationStatus: String, Codable, Equatable, Sendable {
    case success
    case skipped
    case failed
    case partiallyFailed
}

public enum FileOperationFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidRequest(action: FileOperationAction, missingFields: [String])
    case sourceMissing(URL)
    case destinationExists(URL)
    case invalidName(String)
    case sourceEqualsDestination(URL)
    case coordinatorDidNotRun(URL)
    case fileSystem(String)
    case trashFailed(String)
    case replacePartiallyFailed(
        originalDestination: URL,
        trashedDestination: URL,
        underlying: String
    )

    public var description: String {
        switch self {
        case .invalidRequest(let action, let missingFields):
            return "Invalid \(action.rawValue) request. Missing fields: \(missingFields.joined(separator: ", "))"
        case .sourceMissing(let url):
            return "Source does not exist: \(url.path)"
        case .destinationExists(let url):
            return "Destination already exists: \(url.path)"
        case .invalidName(let name):
            return "Invalid file name: \(name)"
        case .sourceEqualsDestination(let url):
            return "Source and destination are the same: \(url.path)"
        case .coordinatorDidNotRun(let url):
            return "File coordinator did not run accessor for: \(url.path)"
        case .fileSystem(let message):
            return "File system operation failed: \(message)"
        case .trashFailed(let message):
            return "Move to Trash failed: \(message)"
        case .replacePartiallyFailed(let originalDestination, let trashedDestination, let underlying):
            return "Replace partially failed after trashing \(originalDestination.path) to \(trashedDestination.path): \(underlying)"
        }
    }
}

public struct FileOperationOutcome: Equatable, Sendable {
    public var action: FileOperationAction
    public var status: FileOperationStatus
    public var sourceURL: URL?
    public var destinationURL: URL?
    public var conflictPolicy: ConflictPolicy
    public var error: FileOperationFailure?
    public var completedOnMainThread: Bool

    public init(
        action: FileOperationAction,
        status: FileOperationStatus,
        sourceURL: URL?,
        destinationURL: URL?,
        conflictPolicy: ConflictPolicy,
        error: FileOperationFailure? = nil,
        completedOnMainThread: Bool
    ) {
        self.action = action
        self.status = status
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.conflictPolicy = conflictPolicy
        self.error = error
        self.completedOnMainThread = completedOnMainThread
    }
}

public struct FileOperationRequest: Sendable {
    public var action: FileOperationAction
    public var sourceURL: URL?
    public var destinationDirectoryURL: URL?
    public var proposedName: String?
    public var conflictPolicy: ConflictPolicy

    public init(
        action: FileOperationAction,
        sourceURL: URL? = nil,
        destinationDirectoryURL: URL? = nil,
        proposedName: String? = nil,
        conflictPolicy: ConflictPolicy = .skip
    ) {
        self.action = action
        self.sourceURL = sourceURL
        self.destinationDirectoryURL = destinationDirectoryURL
        self.proposedName = proposedName
        self.conflictPolicy = conflictPolicy
    }
}

public struct FileOperationFileSystem: Sendable {
    public var fileExists: @Sendable (URL) -> Bool
    public var createDirectory: @Sendable (URL) throws -> Void
    public var copyItem: @Sendable (URL, URL) throws -> Void
    public var moveItem: @Sendable (URL, URL) throws -> Void
    public var trashItem: @Sendable (URL) throws -> URL

    public init(
        fileExists: @escaping @Sendable (URL) -> Bool,
        createDirectory: @escaping @Sendable (URL) throws -> Void,
        copyItem: @escaping @Sendable (URL, URL) throws -> Void,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void,
        trashItem: @escaping @Sendable (URL) throws -> URL
    ) {
        self.fileExists = fileExists
        self.createDirectory = createDirectory
        self.copyItem = copyItem
        self.moveItem = moveItem
        self.trashItem = trashItem
    }

    public static let live = FileOperationFileSystem(
        fileExists: { url in
            FileManager.default.fileExists(atPath: url.path)
        },
        createDirectory: { url in
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false
            )
        },
        copyItem: { source, destination in
            try FileManager.default.copyItem(at: source, to: destination)
        },
        moveItem: { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        },
        trashItem: { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(
                at: url,
                resultingItemURL: &resultingURL
            )
            return (resultingURL as URL?) ?? url
        }
    )
}

public struct FileOperationCoordinator: Sendable {
    public var coordinateWriting: @Sendable (
        URL,
        NSFileCoordinator.WritingOptions,
        @Sendable (URL) throws -> Void
    ) throws -> Void

    public init(
        coordinateWriting: @escaping @Sendable (
            URL,
            NSFileCoordinator.WritingOptions,
            @Sendable (URL) throws -> Void
        ) throws -> Void
    ) {
        self.coordinateWriting = coordinateWriting
    }

    public static let live = FileOperationCoordinator { url, options, body in
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessorResult: Result<Void, Error>?

        coordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            accessorResult = Result {
                try body(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let accessorResult else {
            throw FileOperationFailure.coordinatorDidNotRun(url)
        }
        try accessorResult.get()
    }
}

public struct FileOperationService: Sendable {
    private let fileSystem: FileOperationFileSystem
    private let coordinator: FileOperationCoordinator

    public init(
        fileSystem: FileOperationFileSystem = .live,
        coordinator: FileOperationCoordinator = .live
    ) {
        self.fileSystem = fileSystem
        self.coordinator = coordinator
    }

    public func createFolder(
        named folderName: String,
        in directoryURL: URL,
        conflictPolicy: ConflictPolicy = .skip
    ) async -> FileOperationOutcome {
        await run(action: .createFolder, source: nil, destination: directoryURL.appendingPathComponent(folderName, isDirectory: true), policy: conflictPolicy) {
            try validateName(folderName)
            let destination = try resolveDestination(
                directoryURL.appendingPathComponent(folderName, isDirectory: true),
                policy: conflictPolicy
            )
            try coordinator.coordinateWriting(directoryURL, []) { _ in
                try replaceIfNeeded(destination: destination) {
                    try fileSystem.createDirectory(destination.finalURL)
                }
            }
            return destination.finalURL
        }
    }

    public func rename(
        _ sourceURL: URL,
        to newName: String,
        conflictPolicy: ConflictPolicy = .skip
    ) async -> FileOperationOutcome {
        await run(action: .rename, source: sourceURL, destination: sourceURL.deletingLastPathComponent().appendingPathComponent(newName), policy: conflictPolicy) {
            try validateName(newName)
            guard fileSystem.fileExists(sourceURL) else {
                throw FileOperationFailure.sourceMissing(sourceURL)
            }
            try validateDistinct(
                sourceURL,
                sourceURL.deletingLastPathComponent().appendingPathComponent(newName)
            )
            let destination = try resolveDestination(
                sourceURL.deletingLastPathComponent().appendingPathComponent(newName),
                policy: conflictPolicy
            )
            try coordinator.coordinateWriting(sourceURL, .forMoving) { coordinatedSource in
                try replaceIfNeeded(destination: destination) {
                    try fileSystem.moveItem(coordinatedSource, destination.finalURL)
                }
            }
            return destination.finalURL
        }
    }

    public func copy(
        _ sourceURL: URL,
        to destinationDirectoryURL: URL,
        conflictPolicy: ConflictPolicy = .skip
    ) async -> FileOperationOutcome {
        await run(action: .copy, source: sourceURL, destination: destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent), policy: conflictPolicy) {
            guard fileSystem.fileExists(sourceURL) else {
                throw FileOperationFailure.sourceMissing(sourceURL)
            }
            try validateDistinct(
                sourceURL,
                destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            )
            let destination = try resolveDestination(
                destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent),
                policy: conflictPolicy
            )
            try coordinator.coordinateWriting(destinationDirectoryURL, []) { _ in
                try replaceIfNeeded(destination: destination) {
                    try fileSystem.copyItem(sourceURL, destination.finalURL)
                }
            }
            return destination.finalURL
        }
    }

    public func move(
        _ sourceURL: URL,
        to destinationDirectoryURL: URL,
        conflictPolicy: ConflictPolicy = .skip
    ) async -> FileOperationOutcome {
        await run(action: .move, source: sourceURL, destination: destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent), policy: conflictPolicy) {
            guard fileSystem.fileExists(sourceURL) else {
                throw FileOperationFailure.sourceMissing(sourceURL)
            }
            try validateDistinct(
                sourceURL,
                destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            )
            let destination = try resolveDestination(
                destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent),
                policy: conflictPolicy
            )
            try coordinator.coordinateWriting(sourceURL, .forMoving) { coordinatedSource in
                try replaceIfNeeded(destination: destination) {
                    try fileSystem.moveItem(coordinatedSource, destination.finalURL)
                }
            }
            return destination.finalURL
        }
    }

    public func trash(_ sourceURL: URL) async -> FileOperationOutcome {
        await run(action: .trash, source: sourceURL, destination: nil, policy: .skip) {
            guard fileSystem.fileExists(sourceURL) else {
                throw FileOperationFailure.sourceMissing(sourceURL)
            }
            try coordinator.coordinateWriting(sourceURL, .forDeleting) { coordinatedSource in
                _ = try fileSystem.trashItem(coordinatedSource)
            }
            return nil
        }
    }

    public func perform(_ requests: [FileOperationRequest]) async -> [FileOperationOutcome] {
        var outcomes: [FileOperationOutcome] = []
        for request in requests {
            outcomes.append(await perform(request))
        }
        return outcomes
    }

    public func perform(_ request: FileOperationRequest) async -> FileOperationOutcome {
        switch request.action {
        case .createFolder:
            guard let proposedName = request.proposedName,
                  let destinationDirectoryURL = request.destinationDirectoryURL else {
                return invalidOutcome(for: request, missing: missingFields(
                    ("proposedName", request.proposedName),
                    ("destinationDirectoryURL", request.destinationDirectoryURL)
                ))
            }
            return await createFolder(
                named: proposedName,
                in: destinationDirectoryURL,
                conflictPolicy: request.conflictPolicy
            )
        case .rename:
            guard let sourceURL = request.sourceURL,
                  let proposedName = request.proposedName else {
                return invalidOutcome(for: request, missing: missingFields(
                    ("sourceURL", request.sourceURL),
                    ("proposedName", request.proposedName)
                ))
            }
            return await rename(
                sourceURL,
                to: proposedName,
                conflictPolicy: request.conflictPolicy
            )
        case .copy:
            guard let sourceURL = request.sourceURL,
                  let destinationDirectoryURL = request.destinationDirectoryURL else {
                return invalidOutcome(for: request, missing: missingFields(
                    ("sourceURL", request.sourceURL),
                    ("destinationDirectoryURL", request.destinationDirectoryURL)
                ))
            }
            return await copy(
                sourceURL,
                to: destinationDirectoryURL,
                conflictPolicy: request.conflictPolicy
            )
        case .move:
            guard let sourceURL = request.sourceURL,
                  let destinationDirectoryURL = request.destinationDirectoryURL else {
                return invalidOutcome(for: request, missing: missingFields(
                    ("sourceURL", request.sourceURL),
                    ("destinationDirectoryURL", request.destinationDirectoryURL)
                ))
            }
            return await move(
                sourceURL,
                to: destinationDirectoryURL,
                conflictPolicy: request.conflictPolicy
            )
        case .trash:
            guard let sourceURL = request.sourceURL else {
                return invalidOutcome(for: request, missing: missingFields(
                    ("sourceURL", request.sourceURL)
                ))
            }
            return await trash(sourceURL)
        }
    }

    public func keepingBothURL(for proposedURL: URL) -> URL {
        keepBothURL(for: proposedURL)
    }

    private func run(
        action: FileOperationAction,
        source: URL?,
        destination: URL?,
        policy: ConflictPolicy,
        operation: @escaping @Sendable () throws -> URL?
    ) async -> FileOperationOutcome {
        let task = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let finalDestination = try operation()
                try Task.checkCancellation()
                return FileOperationOutcome(
                    action: action,
                    status: .success,
                    sourceURL: source,
                    destinationURL: finalDestination ?? destination,
                    conflictPolicy: policy,
                    completedOnMainThread: pthread_main_np() != 0
                )
            } catch let failure as FileOperationFailure {
                return FileOperationOutcome(
                    action: action,
                    status: failure.status,
                    sourceURL: source,
                    destinationURL: destination,
                    conflictPolicy: policy,
                    error: failure,
                    completedOnMainThread: pthread_main_np() != 0
                )
            } catch {
                return FileOperationOutcome(
                    action: action,
                    status: .failed,
                    sourceURL: source,
                    destinationURL: destination,
                    conflictPolicy: policy,
                    error: .fileSystem(String(describing: error)),
                    completedOnMainThread: pthread_main_np() != 0
                )
            }
        }
        return await task.value
    }

    private func resolveDestination(
        _ proposedURL: URL,
        policy: ConflictPolicy
    ) throws -> ResolvedDestination {
        guard fileSystem.fileExists(proposedURL) else {
            return ResolvedDestination(
                originalURL: proposedURL,
                finalURL: proposedURL,
                requiresReplace: false
            )
        }

        switch policy {
        case .skip:
            throw FileOperationFailure.destinationExists(proposedURL)
        case .keepBoth:
            return ResolvedDestination(
                originalURL: proposedURL,
                finalURL: keepBothURL(for: proposedURL),
                requiresReplace: false
            )
        case .replace:
            return ResolvedDestination(
                originalURL: proposedURL,
                finalURL: proposedURL,
                requiresReplace: true
            )
        }
    }

    private func replaceIfNeeded(
        destination: ResolvedDestination,
        operation: () throws -> Void
    ) throws {
        guard destination.requiresReplace else {
            try operation()
            return
        }

        let trashedDestination: URL
        do {
            trashedDestination = try fileSystem.trashItem(destination.originalURL)
        } catch {
            throw FileOperationFailure.trashFailed(String(describing: error))
        }

        do {
            try operation()
        } catch let failure as FileOperationFailure {
            throw FileOperationFailure.replacePartiallyFailed(
                originalDestination: destination.originalURL,
                trashedDestination: trashedDestination,
                underlying: failure.description
            )
        } catch {
            throw FileOperationFailure.replacePartiallyFailed(
                originalDestination: destination.originalURL,
                trashedDestination: trashedDestination,
                underlying: String(describing: error)
            )
        }
    }

    private func validateDistinct(_ sourceURL: URL, _ destinationURL: URL) throws {
        let source = sourceURL.standardizedFileURL.path
        let destination = destinationURL.standardizedFileURL.path
        guard source != destination else {
            throw FileOperationFailure.sourceEqualsDestination(destinationURL)
        }
    }

    private func keepBothURL(for proposedURL: URL) -> URL {
        let directory = proposedURL.deletingLastPathComponent()
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        let pathExtension = proposedURL.pathExtension

        var index = 1
        var candidate = proposedURL
        repeat {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let candidateName = baseName + suffix
            candidate = pathExtension.isEmpty
                ? directory.appendingPathComponent(candidateName)
                : directory.appendingPathComponent(candidateName).appendingPathExtension(pathExtension)
            index += 1
        } while fileSystem.fileExists(candidate)

        return candidate
    }

    private func validateName(_ name: String) throws {
        guard name.isEmpty == false,
              name != ".",
              name != "..",
              name.contains("/") == false else {
            throw FileOperationFailure.invalidName(name)
        }
    }

    private func invalidOutcome(
        for request: FileOperationRequest,
        missing fields: [String]
    ) -> FileOperationOutcome {
        FileOperationOutcome(
            action: request.action,
            status: .failed,
            sourceURL: request.sourceURL,
            destinationURL: nil,
            conflictPolicy: request.conflictPolicy,
            error: .invalidRequest(action: request.action, missingFields: fields),
            completedOnMainThread: pthread_main_np() != 0
        )
    }

    private func missingFields(_ fields: (String, Any?)...) -> [String] {
        fields.compactMap { name, value in
            value == nil ? name : nil
        }
    }
}

private struct ResolvedDestination {
    var originalURL: URL
    var finalURL: URL
    var requiresReplace: Bool
}

private extension FileOperationFailure {
    var status: FileOperationStatus {
        switch self {
        case .destinationExists:
            return .skipped
        case .replacePartiallyFailed:
            return .partiallyFailed
        default:
            return .failed
        }
    }
}
