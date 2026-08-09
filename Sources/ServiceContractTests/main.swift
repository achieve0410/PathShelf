import AppKit
import FileOperations
import Foundation
import PreviewFeature

@main
struct ServiceContractTests {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("file operation skip is the default conflict policy", { try testDefaultConflictPolicySkips() }),
            ("keep-both naming is deterministic for files", { try testKeepBothNaming() }),
            ("replace is explicit and routes existing destination to Trash adapter", { try testExplicitReplaceUsesTrashAdapter() }),
            ("missing source reports failure without false success", { try testMissingSourceReportsFailure() }),
            ("batch operations report successful and failed outcomes separately", { try testPartialBatchReporting() }),
            ("trash operation invokes Trash adapter instead of permanent delete", { try testTrashAdapterInvocation() }),
            ("workspace actions route to adapter", { try await testWorkspaceActionRouting() }),
            ("quick look preview contract records present and close state", { try await MainActor.run { try testPreviewContract() } }),
            ("thumbnail cancellation tears down active request state", { try await testThumbnailCancellation() }),
            ("malformed file operation requests fail without adapter calls", { try testMalformedRequestsDoNotCallAdapters() }),
            ("source and destination equality fails before mutation", { try testSourceEqualsDestinationFailsBeforeMutation() }),
            ("replace partial failures preserve trashed destination URL", { try testReplacePartialFailures() }),
            ("mutation coordinator accessor-not-run reports explicit failure", { try testMutationCoordinatorAccessorDidNotRun() }),
            ("thumbnail cancel before handle resumes once and cancels returned handle", { try await testThumbnailCancelBeforeHandleRace() }),
            ("thumbnail completion after cancel is ignored after one terminal transition", { try await testThumbnailCompletionAfterCancelRace() })
        ]

        for (index, test) in tests.enumerated() {
            do {
                try await test.1()
                print("ok \(index + 1) - \(test.0)")
            } catch {
                print("not ok \(index + 1) - \(test.0)")
                print("  \(error)")
                exit(1)
            }
        }

        print("ServiceContractTests: \(tests.count) passed, 0 failed")
    }

    private static func testDefaultConflictPolicySkips() throws {
        let directory = try TemporaryDirectory()
        let service = FileOperationService()
        let folderURL = directory.url.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)

        let outcome = try runAsync {
            await service.createFolder(named: "Existing", in: directory.url)
        }

        try expect(outcome.status == .skipped)
        try expect(outcome.error == .destinationExists(folderURL))
        try expect(FileManager.default.fileExists(atPath: folderURL.path))
    }

    private static func testKeepBothNaming() throws {
        let directory = try TemporaryDirectory()
        let original = directory.url.appendingPathComponent("Report.txt")
        let firstCopy = directory.url.appendingPathComponent("Report copy.txt")
        try Data("original".utf8).write(to: original)
        try Data("copy".utf8).write(to: firstCopy)

        let service = FileOperationService()
        let candidate = service.keepingBothURL(for: original)

        try expect(candidate.lastPathComponent == "Report copy 2.txt")
    }

    private static func testExplicitReplaceUsesTrashAdapter() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("source.txt")
        let destinationDirectory = directory.url.appendingPathComponent("Destination", isDirectory: true)
        let destination = destinationDirectory.appendingPathComponent("source.txt")
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: false)
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)
        let trashRecorder = LockedBox<[URL]>([])
        let fileSystem = FileOperationFileSystem(
            fileExists: { url in FileManager.default.fileExists(atPath: url.path) },
            createDirectory: { url in try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) },
            copyItem: { source, destination in try FileManager.default.copyItem(at: source, to: destination) },
            moveItem: { source, destination in try FileManager.default.moveItem(at: source, to: destination) },
            trashItem: { url in
                trashRecorder.withValue { $0.append(url) }
                try FileManager.default.removeItem(at: url)
                return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
            }
        )
        let service = FileOperationService(fileSystem: fileSystem)

        let outcome = try runAsync {
            await service.copy(source, to: destinationDirectory, conflictPolicy: .replace)
        }

        try expect(outcome.status == .success)
        try expect(outcome.destinationURL == destination)
        try expect(trashRecorder.withValue { $0 } == [destination])
        try expect(String(data: try Data(contentsOf: destination), encoding: .utf8) == "new")
    }

    private static func testMissingSourceReportsFailure() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appendingPathComponent("missing.txt")
        let service = FileOperationService()

        let outcome = try runAsync {
            await service.copy(missing, to: directory.url)
        }

        try expect(outcome.status == .failed)
        try expect(outcome.error == .sourceMissing(missing))
    }

    private static func testPartialBatchReporting() throws {
        let directory = try TemporaryDirectory()
        let service = FileOperationService()
        let missing = directory.url.appendingPathComponent("missing.txt")
        let requests = [
            FileOperationRequest(
                action: .createFolder,
                destinationDirectoryURL: directory.url,
                proposedName: "Created"
            ),
            FileOperationRequest(
                action: .move,
                sourceURL: missing,
                destinationDirectoryURL: directory.url
            )
        ]

        let outcomes = try runAsync {
            await service.perform(requests)
        }

        try expect(outcomes.count == 2)
        try expect(outcomes[0].status == .success)
        try expect(outcomes[1].status == .failed)
        try expect(outcomes[1].error == .sourceMissing(missing))
    }

    private static func testTrashAdapterInvocation() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("trash-me.txt")
        try Data("trash".utf8).write(to: file)
        let calls = LockedBox<[URL]>([])
        let fileSystem = FileOperationFileSystem(
            fileExists: { url in FileManager.default.fileExists(atPath: url.path) },
            createDirectory: { _ in },
            copyItem: { _, _ in },
            moveItem: { _, _ in },
            trashItem: { url in
                calls.withValue { $0.append(url) }
                return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
            }
        )
        let service = FileOperationService(fileSystem: fileSystem)

        let outcome = try runAsync {
            await service.trash(file)
        }

        try expect(outcome.status == .success)
        try expect(calls.withValue { $0 } == [file])
        try expect(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    private static func testWorkspaceActionRouting() async throws {
        let item = URL(fileURLWithPath: "/tmp/item.txt")
        let app = URL(fileURLWithPath: "/Applications/TextEdit.app")
        let calls = LockedBox<[WorkspaceAction]>([])
        let service = WorkspaceActionService(
            adapter: WorkspaceActionAdapter(
                open: { url in
                    calls.withValue { $0.append(.openDefault(url)) }
                    return true
                },
                applications: { url in
                    calls.withValue { $0.append(.openDefault(url)) }
                    return [WorkspaceApplication(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit", url: app)]
                },
                openWithApplication: { item, application, completion in
                    calls.withValue { $0.append(.openWith(item: item, application: application)) }
                    completion(nil)
                },
                reveal: { url in
                    calls.withValue { $0.append(.revealInFinder(url)) }
                    return true
                }
            )
        )

        try service.openDefault(item)
        let apps = service.compatibleApplications(for: item)
        try await service.open(item, with: app)
        try service.revealInFinder(item)

        try expect(apps == [WorkspaceApplication(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit", url: app)])
        try expect(calls.withValue { $0 } == [
            .openDefault(item),
            .openDefault(item),
            .openWith(item: item, application: app),
            .revealInFinder(item)
        ])
    }

    @MainActor
    private static func testPreviewContract() throws {
        let controller = QuickLookPreviewController()
        let item = PreviewItem(url: URL(fileURLWithPath: "/tmp/example.txt"))

        controller.present(item)
        try expect(controller.state == .presenting(item))
        try expect(controller.presentedItems == [item])

        controller.close()
        try expect(controller.state == .closed)
        try expect(controller.presentedItems.isEmpty)

    }

    private static func testThumbnailCancellation() async throws {
        final class FakeRequest: CancellableThumbnailRequest, @unchecked Sendable {
            let onCancel: () -> Void

            init(onCancel: @escaping () -> Void) {
                self.onCancel = onCancel
            }

            func cancel() {
                onCancel()
            }
        }

        let canceledIDs = LockedBox<[UUID]>([])
        let generatorStarted = TestSignal()
        let service = ThumbnailService { request, completion in
            generatorStarted.signal()
            return FakeRequest {
                canceledIDs.withValue { $0.append(request.id) }
                completion(.failure(ThumbnailError.canceled(request.id)))
            }
        }
        let request = ThumbnailRequest(url: URL(fileURLWithPath: "/tmp/thumb.txt"))
        let task = Task {
            try await service.thumbnail(for: request)
        }

        try await awaitSignal(generatorStarted, "thumbnail generator start")
        task.cancel()
        do {
            _ = try await task.value
            throw ContractTestFailure("Expected thumbnail cancellation")
        } catch ThumbnailError.canceled(let id) {
            try expect(id == request.id)
        }

        try expect(canceledIDs.withValue { $0 } == [request.id])
        try expect(service.snapshot.startedCount == 1)
        try expect(service.snapshot.canceledCount == 1)
    }

    private static func testMalformedRequestsDoNotCallAdapters() throws {
        let callCount = LockedBox(0)
        let service = FileOperationService(
            fileSystem: countingFileSystem(callCount: callCount),
            coordinator: FileOperationCoordinator { _, _, _ in
                callCount.withValue { $0 += 1 }
            }
        )
        let requests = [
            FileOperationRequest(action: .createFolder),
            FileOperationRequest(action: .rename),
            FileOperationRequest(action: .copy),
            FileOperationRequest(action: .move),
            FileOperationRequest(action: .trash)
        ]

        let outcomes = try runAsync {
            await service.perform(requests)
        }

        try expect(outcomes.count == requests.count)
        try expect(outcomes.allSatisfy { $0.status == .failed })
        try expect(outcomes[0].error == .invalidRequest(action: .createFolder, missingFields: ["proposedName", "destinationDirectoryURL"]))
        try expect(outcomes[1].error == .invalidRequest(action: .rename, missingFields: ["sourceURL", "proposedName"]))
        try expect(outcomes[2].error == .invalidRequest(action: .copy, missingFields: ["sourceURL", "destinationDirectoryURL"]))
        try expect(outcomes[3].error == .invalidRequest(action: .move, missingFields: ["sourceURL", "destinationDirectoryURL"]))
        try expect(outcomes[4].error == .invalidRequest(action: .trash, missingFields: ["sourceURL"]))
        try expect(callCount.withValue { $0 } == 0)
    }

    private static func testSourceEqualsDestinationFailsBeforeMutation() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("same.txt")
        try Data("same".utf8).write(to: file)
        let mutationCount = LockedBox(0)
        let service = FileOperationService(
            fileSystem: FileOperationFileSystem(
                fileExists: { url in FileManager.default.fileExists(atPath: url.path) },
                createDirectory: { _ in mutationCount.withValue { $0 += 1 } },
                copyItem: { _, _ in mutationCount.withValue { $0 += 1 } },
                moveItem: { _, _ in mutationCount.withValue { $0 += 1 } },
                trashItem: { url in
                    mutationCount.withValue { $0 += 1 }
                    return url
                }
            )
        )

        let renameOutcome = try runAsync {
            await service.rename(file, to: "same.txt", conflictPolicy: .replace)
        }
        let copyOutcome = try runAsync {
            await service.copy(file, to: directory.url, conflictPolicy: .replace)
        }
        let moveOutcome = try runAsync {
            await service.move(file, to: directory.url, conflictPolicy: .replace)
        }

        try expect(renameOutcome.error == .sourceEqualsDestination(file))
        try expect(copyOutcome.error == .sourceEqualsDestination(file))
        try expect(moveOutcome.error == .sourceEqualsDestination(file))
        try expect(mutationCount.withValue { $0 } == 0)
    }

    private static func testReplacePartialFailures() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("source.txt")
        let renameSource = directory.url.appendingPathComponent("rename-source.txt")
        let moveSource = directory.url.appendingPathComponent("move-source.txt")
        let destinationDirectory = directory.url.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: false)
        try Data("source".utf8).write(to: source)
        try Data("rename".utf8).write(to: renameSource)
        try Data("move".utf8).write(to: moveSource)

        let trashedBase = URL(fileURLWithPath: "/RecoverableTrash", isDirectory: true)
        let service = FileOperationService(
            fileSystem: FileOperationFileSystem(
                fileExists: { _ in true },
                createDirectory: { _ in throw SyntheticError("create failed") },
                copyItem: { _, _ in throw SyntheticError("copy failed") },
                moveItem: { _, destination in throw SyntheticError("move failed to \(destination.lastPathComponent)") },
                trashItem: { url in trashedBase.appendingPathComponent(url.lastPathComponent) }
            )
        )

        let createDestination = directory.url.appendingPathComponent("Existing", isDirectory: true)
        let renameDestination = directory.url.appendingPathComponent("renamed.txt")
        let copyDestination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        let moveDestination = destinationDirectory.appendingPathComponent(moveSource.lastPathComponent)

        let createOutcome = try runAsync {
            await service.createFolder(named: "Existing", in: directory.url, conflictPolicy: .replace)
        }
        let renameOutcome = try runAsync {
            await service.rename(renameSource, to: "renamed.txt", conflictPolicy: .replace)
        }
        let copyOutcome = try runAsync {
            await service.copy(source, to: destinationDirectory, conflictPolicy: .replace)
        }
        let moveOutcome = try runAsync {
            await service.move(moveSource, to: destinationDirectory, conflictPolicy: .replace)
        }

        try expect(createOutcome.status == .partiallyFailed)
        try expect(createOutcome.error == .replacePartiallyFailed(
            originalDestination: createDestination,
            trashedDestination: trashedBase.appendingPathComponent("Existing"),
            underlying: "create failed"
        ))
        try expect(renameOutcome.status == .partiallyFailed)
        try expect(renameOutcome.error == .replacePartiallyFailed(
            originalDestination: renameDestination,
            trashedDestination: trashedBase.appendingPathComponent("renamed.txt"),
            underlying: "move failed to renamed.txt"
        ))
        try expect(copyOutcome.status == .partiallyFailed)
        try expect(copyOutcome.error == .replacePartiallyFailed(
            originalDestination: copyDestination,
            trashedDestination: trashedBase.appendingPathComponent("source.txt"),
            underlying: "copy failed"
        ))
        try expect(moveOutcome.status == .partiallyFailed)
        try expect(moveOutcome.error == .replacePartiallyFailed(
            originalDestination: moveDestination,
            trashedDestination: trashedBase.appendingPathComponent("move-source.txt"),
            underlying: "move failed to move-source.txt"
        ))
    }

    private static func testMutationCoordinatorAccessorDidNotRun() throws {
        let directory = try TemporaryDirectory()
        let service = FileOperationService(
            coordinator: FileOperationCoordinator { url, _, _ in
                throw FileOperationFailure.coordinatorDidNotRun(url)
            }
        )

        let outcome = try runAsync {
            await service.createFolder(named: "NoAccessor", in: directory.url)
        }

        try expect(outcome.status == .failed)
        try expect(outcome.error == .coordinatorDidNotRun(directory.url))
    }

    private static func testThumbnailCancelBeforeHandleRace() async throws {
        final class FakeRequest: CancellableThumbnailRequest, @unchecked Sendable {
            let cancelCount: LockedBox<Int>

            init(cancelCount: LockedBox<Int>) {
                self.cancelCount = cancelCount
            }

            func cancel() {
                cancelCount.withValue { $0 += 1 }
            }
        }

        let generatorEntered = TestSignal()
        let allowGeneratorReturn = DispatchSemaphore(value: 0)
        let cancelCount = LockedBox(0)
        let service = ThumbnailService { _, _ in
            generatorEntered.signal()
            _ = allowGeneratorReturn.wait(timeout: .now() + 2)
            return FakeRequest(cancelCount: cancelCount)
        }
        let request = ThumbnailRequest(url: URL(fileURLWithPath: "/tmp/race-before-handle.txt"))
        let task = Task {
            try await service.thumbnail(for: request)
        }

        try await awaitSignal(generatorEntered, "cancel-before-handle generator entry")
        task.cancel()
        allowGeneratorReturn.signal()

        do {
            _ = try await task.value
            throw ContractTestFailure("Expected thumbnail cancellation")
        } catch ThumbnailError.canceled(let id) {
            try expect(id == request.id)
        }
        try expect(cancelCount.withValue { $0 } == 1)
        try expect(service.snapshot.completedCount == 0)
    }

    private static func testThumbnailCompletionAfterCancelRace() async throws {
        final class FakeRequest: CancellableThumbnailRequest, @unchecked Sendable {
            let cancelCount: LockedBox<Int>

            init(cancelCount: LockedBox<Int>) {
                self.cancelCount = cancelCount
            }

            func cancel() {
                cancelCount.withValue { $0 += 1 }
            }
        }

        let completionBox = LockedBox<(@Sendable (Result<ThumbnailResult, Error>) -> Void)?>(nil)
        let completionCaptured = TestSignal()
        let cancelCount = LockedBox(0)
        let service = ThumbnailService { _, completion in
            completionBox.withValue { $0 = completion }
            completionCaptured.signal()
            return FakeRequest(cancelCount: cancelCount)
        }
        let request = ThumbnailRequest(url: URL(fileURLWithPath: "/tmp/completion-after-cancel.txt"))
        let task = Task {
            try await service.thumbnail(for: request)
        }

        try await awaitSignal(completionCaptured, "thumbnail completion capture")
        task.cancel()

        completionBox.withValue { completion in
            completion?(.failure(ThumbnailError.generationFailed(request.id, "late completion")))
        }

        do {
            _ = try await task.value
            throw ContractTestFailure("Expected thumbnail cancellation")
        } catch ThumbnailError.canceled(let id) {
            try expect(id == request.id)
        }
        try expect(cancelCount.withValue { $0 } == 1)
        try expect(service.snapshot.activeRequestCount == 0)
        try expect(service.snapshot.canceledCount == 1)
        try expect(service.snapshot.completedCount == 0)

        do {
            try await awaitSignal(
                TestSignal(),
                "missing thumbnail signal",
                timeout: .milliseconds(20)
            )
            throw ContractTestFailure("Expected bounded signal timeout")
        } catch let failure as ContractTestFailure {
            try expect(failure.description == "Timed out waiting for missing thumbnail signal")
        }
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ description: String = "Expectation failed"
    ) throws {
        guard try condition() else {
            throw ContractTestFailure(description)
        }
    }

    private static func runAsync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<Result<T, Error>?>(nil)

        let task = Task.detached {
            let result: Result<T, Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            box.withValue { value in
                value = result
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            task.cancel()
            throw ContractTestFailure("Timed out waiting for asynchronous operation")
        }
        return try box.withValue { value in
            guard let value else {
                throw ContractTestFailure("Async operation did not produce a result")
            }
            return try value.get()
        }
    }

    private static func awaitSignal(
        _ signal: TestSignal,
        _ description: String,
        timeout: Duration = .seconds(2)
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await signal.wait()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ContractTestFailure("Timed out waiting for \(description)")
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private static func countingFileSystem(callCount: LockedBox<Int>) -> FileOperationFileSystem {
        FileOperationFileSystem(
            fileExists: { _ in
                callCount.withValue { $0 += 1 }
                return false
            },
            createDirectory: { _ in callCount.withValue { $0 += 1 } },
            copyItem: { _, _ in callCount.withValue { $0 += 1 } },
            moveItem: { _, _ in callCount.withValue { $0 += 1 } },
            trashItem: { url in
                callCount.withValue { $0 += 1 }
                return url
            }
        )
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/test-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
}

private struct ContractTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct SyntheticError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

private final class TestSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var canceledWaiters: Set<UUID> = []

    func signal() {
        let continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        if let id = continuations.keys.first {
            continuation = continuations.removeValue(forKey: id)
        } else {
            isSignaled = true
            continuation = nil
        }
        lock.unlock()
        continuation?.resume()
    }

    func wait() async throws {
        let id = UUID()
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResume: Bool
                lock.lock()
                if isSignaled {
                    isSignaled = false
                    shouldResume = true
                } else if canceledWaiters.remove(id) != nil {
                    shouldResume = true
                } else {
                    continuations[id] = continuation
                    shouldResume = false
                }
                lock.unlock()
                if shouldResume {
                    continuation.resume()
                }
            }
            try Task.checkCancellation()
        } onCancel: {
            let continuation: CheckedContinuation<Void, Never>?
            self.lock.lock()
            if let current = self.continuations.removeValue(forKey: id) {
                continuation = current
            } else {
                self.canceledWaiters.insert(id)
                continuation = nil
            }
            self.lock.unlock()
            continuation?.resume()
        }
    }
}
