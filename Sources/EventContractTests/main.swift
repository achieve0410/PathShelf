import FileAccess
import Foundation
import PanelFeature

@main
struct EventContractTests {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("visible directory monitor starts replaces and stops one active stream", testVisibleMonitorLifecycle),
            ("visible directory monitor coalesces duplicate burst callbacks", testVisibleMonitorBurstCoalescing),
            ("visible directory monitor ignores stale generation callbacks", testVisibleMonitorIgnoresStaleCallbacks),
            ("visible directory monitor records post-close callbacks without UI mutation", testVisibleMonitorPostCloseCallback),
            ("volume observer starts stops and ignores post-close notifications", testVolumeObserverLifecycle),
            ("external state maps iCloud placeholder without app download ownership", testICloudPlaceholderMapping),
            ("external state maps unavailable network mount distinctly", testUnavailableNetworkMountMapping),
            ("external state preserves stale and permission-denied failures", testStaleAndPermissionMapping),
            ("manual retry recovers saved location without losing identity", testManualRetryRecovery),
            ("manual retry maps missing removable kind to disconnected with identity", testMissingRemovableKindMapsDisconnected),
            ("manual retry maps missing network kind to network unavailable with identity", testMissingNetworkKindMapsUnavailable),
            ("accessible probe updates kind cache before subsequent missing transition", testAccessibleProbeCachesExternalKind),
            ("add caches network kind before missing retry transition", testAddCachesNetworkKindBeforeMissingRetry),
            ("add caches removable kind before missing retry transition", testAddCachesRemovableKindBeforeMissingRetry),
            ("volume loss downgrades available removable location and closes active scope", testVolumeLossDowngradesAvailableRemovableLocation),
            ("volume loss downgrades available network location with identity", testVolumeLossDowngradesAvailableNetworkLocation),
            ("navigating recovered saved location enters usable available state", testRecoveredLocationBecomesUsable),
            ("model teardown leaves observer thumbnail timer and animation counters zero", testModelTeardownDiagnostics),
            ("live FSEvents stream can be created and stopped without polling timers", testLiveFSEventsCreationProof)
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

        print("EventContractTests: \(tests.count) passed, 0 failed")
    }

    private static func testVisibleMonitorLifecycle() async throws {
        let source = TestDirectoryEventSource()
        let diagnostics = LifecycleDiagnostics()
        let monitor = VisibleDirectoryMonitor(source: source.source, diagnostics: diagnostics)
        let first = URL(fileURLWithPath: "/tmp/first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/second", isDirectory: true)

        monitor.start(root: first) { _, _ in }
        try expect(source.streams.map(\.root) == [first])
        try expect(diagnostics.snapshot.activeVisibleDirectoryObserverCount == 1)

        monitor.replaceRoot(second) { _, _ in }
        try expect(source.streams[0].isStopped)
        try expect(source.streams.map(\.root) == [first, second])
        try expect(diagnostics.snapshot.activeVisibleDirectoryObserverCount == 1)

        monitor.stop()
        try expect(source.streams[1].isStopped)
        try expect(diagnostics.snapshot.activeVisibleDirectoryObserverCount == 0)
        try expect(diagnostics.snapshot.visibleDirectoryObserverStartCount == 2)
        try expect(diagnostics.snapshot.visibleDirectoryObserverStopCount == 2)
    }

    private static func testVisibleMonitorBurstCoalescing() async throws {
        let source = TestDirectoryEventSource()
        let diagnostics = LifecycleDiagnostics()
        let monitor = VisibleDirectoryMonitor(source: source.source, diagnostics: diagnostics)
        let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let delivered = LockedBox(0)

        monitor.start(root: root) { _, _ in
            delivered.withValue { $0 += 1 }
        }
        source.streams[0].emit(root)
        source.streams[0].emit(root)
        await pumpMainActor()

        try expect(delivered.withValue { $0 } == 1)
        try expect(diagnostics.snapshot.callbackCount == 2)
        try expect(diagnostics.snapshot.postCloseCallbackCount == 0)
    }

    private static func testVisibleMonitorIgnoresStaleCallbacks() async throws {
        let source = TestDirectoryEventSource()
        let diagnostics = LifecycleDiagnostics()
        let monitor = VisibleDirectoryMonitor(source: source.source, diagnostics: diagnostics)
        let delivered = LockedBox(0)

        monitor.start(root: URL(fileURLWithPath: "/tmp/one")) { _, _ in
            delivered.withValue { $0 += 1 }
        }
        monitor.replaceRoot(URL(fileURLWithPath: "/tmp/two")) { _, _ in
            delivered.withValue { $0 += 1 }
        }
        source.streams[0].emit(URL(fileURLWithPath: "/tmp/one"))
        await pumpMainActor()

        try expect(delivered.withValue { $0 } == 0)
        try expect(diagnostics.snapshot.callbackCount == 1)
        try expect(diagnostics.snapshot.staleCallbackCount == 1)
        try expect(diagnostics.snapshot.postCloseCallbackCount == 0)
        try expect(diagnostics.snapshot.uiMutationCount == 0)
    }

    private static func testVisibleMonitorPostCloseCallback() async throws {
        let source = TestDirectoryEventSource()
        let diagnostics = LifecycleDiagnostics()
        let monitor = VisibleDirectoryMonitor(source: source.source, diagnostics: diagnostics)
        let delivered = LockedBox(0)

        monitor.start(root: URL(fileURLWithPath: "/tmp/root")) { _, _ in
            delivered.withValue { $0 += 1 }
        }
        monitor.stop()
        source.streams[0].emit(URL(fileURLWithPath: "/tmp/root"))
        await pumpMainActor()

        try expect(delivered.withValue { $0 } == 0)
        try expect(diagnostics.snapshot.postCloseCallbackCount == 1)
        try expect(diagnostics.snapshot.uiMutationCount == 0)
    }

    private static func testVolumeObserverLifecycle() async throws {
        let source = TestVolumeEventSource()
        let diagnostics = LifecycleDiagnostics()
        let observer = VolumeEventObserver(source: source.source, diagnostics: diagnostics)
        let delivered = LockedBox(0)

        observer.start { _ in
            delivered.withValue { $0 += 1 }
        }
        source.stream?.emit(VolumeEvent(url: URL(fileURLWithPath: "/Volumes/Disk"), kind: .mounted))
        await pumpMainActor()
        observer.stop()
        source.stream?.emit(VolumeEvent(url: URL(fileURLWithPath: "/Volumes/Disk"), kind: .unmounted))
        await pumpMainActor()

        try expect(delivered.withValue { $0 } == 1)
        try expect(diagnostics.snapshot.activeVolumeObserverCount == 0)
        try expect(diagnostics.snapshot.volumeObserverStartCount == 1)
        try expect(diagnostics.snapshot.volumeObserverStopCount == 1)
        try expect(diagnostics.snapshot.postCloseCallbackCount == 1)
    }

    private static func testICloudPlaceholderMapping() async throws {
        let metadata = ExternalLocationMetadata(
            exists: true,
            isUbiquitousItem: true,
            ubiquitousDownloadState: .notDownloaded
        )
        let availability = ExternalLocationStateResolver.availability(
            current: .available,
            resolution: availableResolution(url: URL(fileURLWithPath: "/tmp/iCloud")),
            metadata: metadata,
            lastKnownExternalKind: nil,
            markRecovered: false
        )

        try expect(availability == .iCloudPlaceholder)
    }

    private static func testUnavailableNetworkMountMapping() async throws {
        let metadata = ExternalLocationMetadata(
            exists: false,
            isRemovable: false,
            isLocalVolume: false
        )
        let availability = ExternalLocationStateResolver.availability(
            current: .available,
            resolution: availableResolution(url: URL(fileURLWithPath: "/Volumes/Share")),
            metadata: metadata,
            lastKnownExternalKind: nil,
            markRecovered: false
        )

        try expect(availability == .networkUnavailable)
    }

    private static func testStaleAndPermissionMapping() async throws {
        let stale = BookmarkResolution(
            scopedURL: nil,
            originalPath: "/tmp/stale",
            isStale: true,
            availability: .staleBookmark,
            error: .staleBookmark(originalPath: "/tmp/stale")
        )
        let denied = BookmarkResolution(
            scopedURL: nil,
            originalPath: "/tmp/denied",
            isStale: false,
            availability: .permissionDenied,
            error: .permissionDenied(originalPath: "/tmp/denied")
        )

        try expect(
            ExternalLocationStateResolver.availability(
                current: .available,
                resolution: stale,
                metadata: nil,
                lastKnownExternalKind: nil,
                markRecovered: true
            ) == .staleBookmark
        )
        try expect(
            ExternalLocationStateResolver.availability(
                current: .available,
                resolution: denied,
                metadata: nil,
                lastKnownExternalKind: nil,
                markRecovered: true
            ) == .permissionDenied
        )
    }

    private static func testManualRetryRecovery() async throws {
        let fixture = try TemporaryDirectory()
        let bookmarkService = SecurityScopedBookmarkService()
        let bookmark = try bookmarkService.makeBookmark(for: fixture.url)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let stored = LockedBox([
            SavedLocation(
                id: id,
                displayName: "External",
                bookmark: bookmark,
                sortOrder: 0,
                availability: .unavailable
            )
        ])
        let model = try await runMain {
            makeModel(stored: stored, bookmarkService: bookmarkService)
        }

        await model.loadInitialState()
        try await model.retrySavedLocation(id: id)

        let saved = stored.withValue { $0 }
        try expect(saved.count == 1)
        try expect(saved[0].id == id)
        try expect(saved[0].availability == .recovered)
    }

    private static func testMissingRemovableKindMapsDisconnected() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let stored = LockedBox([
            unavailableLocation(id: id, kind: .removable)
        ])
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: SecurityScopedBookmarkService(),
                resolveBookmark: { bookmark in
                    missingResolution(path: bookmark.originalPath)
                }
            )
        }

        await model.loadInitialState()
        try await model.retrySavedLocation(id: id)

        let saved = stored.withValue { $0 }
        try expect(saved[0].id == id)
        try expect(saved[0].availability == .disconnected)
        try expect(saved[0].lastKnownExternalKind == .removable)
    }

    private static func testMissingNetworkKindMapsUnavailable() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let stored = LockedBox([
            unavailableLocation(id: id, kind: .network)
        ])
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: SecurityScopedBookmarkService(),
                resolveBookmark: { bookmark in
                    missingResolution(path: bookmark.originalPath)
                }
            )
        }

        await model.loadInitialState()
        try await model.retrySavedLocation(id: id)

        let saved = stored.withValue { $0 }
        try expect(saved[0].id == id)
        try expect(saved[0].availability == .networkUnavailable)
        try expect(saved[0].lastKnownExternalKind == .network)
    }

    private static func testAccessibleProbeCachesExternalKind() async throws {
        let fixture = try TemporaryDirectory()
        let bookmarkService = SecurityScopedBookmarkService()
        let bookmark = try bookmarkService.makeBookmark(for: fixture.url)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let shouldResolve = LockedBox(true)
        let stored = LockedBox([
            SavedLocation(
                id: id,
                displayName: "Cached Network",
                bookmark: bookmark,
                sortOrder: 0,
                availability: .unavailable
            )
        ])
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: bookmarkService,
                resolveBookmark: { bookmark in
                    if shouldResolve.withValue({ $0 }) {
                        return bookmarkService.resolve(bookmark)
                    }
                    return missingResolution(path: bookmark.originalPath)
                },
                metadata: { url in
                    ExternalLocationMetadata(exists: true, isLocalVolume: false)
                }
            )
        }

        await model.loadInitialState()
        try await model.retrySavedLocation(id: id)
        try expect(stored.withValue { $0[0].lastKnownExternalKind } == .network)
        shouldResolve.withValue { $0 = false }
        try await model.retrySavedLocation(id: id)

        let saved = stored.withValue { $0 }
        try expect(saved[0].id == id)
        try expect(saved[0].availability == .networkUnavailable)
        try expect(saved[0].lastKnownExternalKind == .network)
    }

    private static func testAddCachesNetworkKindBeforeMissingRetry() async throws {
        let fixture = try TemporaryDirectory()
        let bookmarkService = SecurityScopedBookmarkService()
        let shouldResolve = LockedBox(true)
        let stored = LockedBox<[SavedLocation]>([])
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: bookmarkService,
                resolveBookmark: { bookmark in
                    if shouldResolve.withValue({ $0 }) {
                        return bookmarkService.resolve(bookmark)
                    }
                    return missingResolution(path: bookmark.originalPath)
                },
                metadata: { _ in
                    ExternalLocationMetadata(exists: true, isLocalVolume: false)
                }
            )
        }

        try await runMain {
            try model.addSavedLocation(url: fixture.url, displayName: "Network")
        }
        let added = stored.withValue { $0[0] }
        try expect(added.lastKnownExternalKind == .network)
        shouldResolve.withValue { $0 = false }
        try await model.retrySavedLocation(id: added.id)

        let saved = stored.withValue { $0[0] }
        try expect(saved.id == added.id)
        try expect(saved.availability == .networkUnavailable)
        try expect(saved.lastKnownExternalKind == .network)
    }

    private static func testAddCachesRemovableKindBeforeMissingRetry() async throws {
        let fixture = try TemporaryDirectory()
        let bookmarkService = SecurityScopedBookmarkService()
        let shouldResolve = LockedBox(true)
        let stored = LockedBox<[SavedLocation]>([])
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: bookmarkService,
                resolveBookmark: { bookmark in
                    if shouldResolve.withValue({ $0 }) {
                        return bookmarkService.resolve(bookmark)
                    }
                    return missingResolution(path: bookmark.originalPath)
                },
                metadata: { _ in
                    ExternalLocationMetadata(exists: true, isRemovable: true)
                }
            )
        }

        try await runMain {
            try model.addSavedLocation(url: fixture.url, displayName: "Removable")
        }
        let added = stored.withValue { $0[0] }
        try expect(added.lastKnownExternalKind == .removable)
        shouldResolve.withValue { $0 = false }
        try await model.retrySavedLocation(id: added.id)

        let saved = stored.withValue { $0[0] }
        try expect(saved.id == added.id)
        try expect(saved.availability == .disconnected)
        try expect(saved.lastKnownExternalKind == .removable)
    }

    private static func testVolumeLossDowngradesAvailableRemovableLocation() async throws {
        let mount = try TemporaryDirectory()
        let savedRoot = mount.url.appendingPathComponent("Saved", isDirectory: true)
        try FileManager.default.createDirectory(at: savedRoot, withIntermediateDirectories: false)
        try Data("stale".utf8).write(to: savedRoot.appendingPathComponent("stale.txt"))
        let closeCount = LockedBox(0)
        let bookmarkService = scopedBookmarkService(closeCount: closeCount)
        let bookmark = try bookmarkService.makeBookmark(for: savedRoot)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let stored = LockedBox([
            SavedLocation(
                id: id,
                displayName: "USB",
                bookmark: bookmark,
                sortOrder: 0,
                availability: .available,
                lastKnownExternalKind: .removable
            )
        ])
        let diagnostics = LifecycleDiagnostics()
        let directorySource = TestDirectoryEventSource()
        let volumeSource = TestVolumeEventSource()
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: bookmarkService,
                diagnostics: diagnostics,
                directorySource: directorySource.source,
                volumeSource: volumeSource.source,
                metadata: { _ in ExternalLocationMetadata(exists: true, isRemovable: true) },
                closeSecurityScopedURL: { _ in closeCount.withValue { $0 += 1 } }
            )
        }

        await model.loadInitialState()
        try await model.navigateToSavedLocation(id: id)
        let itemNames = try await runMain { model.items.map(\.name) }
        try expect(itemNames == ["stale.txt"])
        try await runMain { model.selectFirstItem(named: "stale.txt") }
        await model.startLifecycleMonitoring()
        try expect(
            NavigationAccessPolicy(homeRoot: mount.url).isInsideScopedRoot(savedRoot, scopedRoot: mount.url),
            "test policy did not recognize saved root under mount"
        )
        try expect(volumeSource.stream != nil, "volume stream was not started")
        volumeSource.stream?.emit(VolumeEvent(url: mount.url, kind: .unmounted))
        await pumpMainActor()

        let saved = stored.withValue { $0[0] }
        try expect(saved.id == id, "identity changed")
        try expect(saved.availability == .disconnected, "availability was \(saved.availability)")
        try expect(saved.lastKnownExternalKind == .removable, "kind was \(String(describing: saved.lastKnownExternalKind))")
        try expect(closeCount.withValue { $0 } == 1, "close count was \(closeCount.withValue { $0 })")
        let snapshot = try await runMain { model.snapshot }
        try expect(snapshot.itemNames.isEmpty, "stale items remained \(snapshot.itemNames)")
        try expect(snapshot.selectedItemName == nil, "selection was not cleared")
        try expect(
            snapshot.availability == .unavailable(
                .disconnected,
                savedRoot.standardizedFileURL.path
            ),
            "snapshot availability was \(snapshot.availability)"
        )
        try expect(snapshot.lastErrorMessage?.contains("disconnected") == true, "message was \(snapshot.lastErrorMessage ?? "nil")")
        try expect(snapshot.lifecycleDiagnostics.activeVisibleDirectoryObserverCount == 0)
    }

    private static func testVolumeLossDowngradesAvailableNetworkLocation() async throws {
        let mount = try TemporaryDirectory()
        let savedRoot = mount.url.appendingPathComponent("Share", isDirectory: true)
        try FileManager.default.createDirectory(at: savedRoot, withIntermediateDirectories: false)
        let bookmarkService = scopedBookmarkService(closeCount: LockedBox(0))
        let bookmark = try bookmarkService.makeBookmark(for: savedRoot)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let stored = LockedBox([
            SavedLocation(
                id: id,
                displayName: "Share",
                bookmark: bookmark,
                sortOrder: 0,
                availability: .available,
                lastKnownExternalKind: .network
            )
        ])
        let volumeSource = TestVolumeEventSource()
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: bookmarkService,
                volumeSource: volumeSource.source,
                metadata: { _ in ExternalLocationMetadata(exists: true, isLocalVolume: false) }
            )
        }

        await model.loadInitialState()
        try await model.navigateToSavedLocation(id: id)
        await model.startLifecycleMonitoring()
        await pumpMainActor()
        try expect(volumeSource.stream != nil, "volume stream was not started")
        volumeSource.stream?.emit(VolumeEvent(url: mount.url, kind: .unmounted))
        await pumpMainActor()

        let saved = stored.withValue { $0[0] }
        try expect(saved.id == id, "identity changed")
        try expect(saved.availability == .networkUnavailable, "availability was \(saved.availability)")
        try expect(saved.lastKnownExternalKind == .network, "kind was \(String(describing: saved.lastKnownExternalKind))")
        let snapshot = try await runMain { model.snapshot }
        try expect(
            snapshot.availability == .unavailable(
                .networkUnavailable,
                savedRoot.standardizedFileURL.path
            ),
            "snapshot availability was \(snapshot.availability)"
        )
        try expect(snapshot.itemNames.isEmpty)
    }

    private static func testRecoveredLocationBecomesUsable() async throws {
        let fixture = try TemporaryDirectory()
        try Data("alpha".utf8).write(to: fixture.url.appendingPathComponent("alpha.txt"))
        let bookmarkService = SecurityScopedBookmarkService()
        let bookmark = try bookmarkService.makeBookmark(for: fixture.url)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let stored = LockedBox([
            SavedLocation(
                id: id,
                displayName: "Recovered",
                bookmark: bookmark,
                sortOrder: 0,
                availability: .recovered
            )
        ])
        let model = try await runMain {
            makeModel(stored: stored, bookmarkService: bookmarkService)
        }

        await model.loadInitialState()
        try await model.navigateToSavedLocation(id: id)

        let snapshot = try await runMain { model.snapshot }
        try expect(snapshot.itemNames == ["alpha.txt"])
        try expect(stored.withValue { $0[0].availability } == .available)
    }

    private static func testModelTeardownDiagnostics() async throws {
        let directorySource = TestDirectoryEventSource()
        let volumeSource = TestVolumeEventSource()
        let diagnostics = LifecycleDiagnostics()
        let stored = LockedBox<[SavedLocation]>([])
        let model = try await runMain {
            makeModel(
                stored: stored,
                bookmarkService: SecurityScopedBookmarkService(),
                diagnostics: diagnostics,
                directorySource: directorySource.source,
                volumeSource: volumeSource.source
            )
        }

        await model.loadInitialState()
        await model.startLifecycleMonitoring()
        await model.setActiveThumbnailCount(3)
        await model.teardown()

        let snapshot = try await runMain { model.snapshot.lifecycleDiagnostics }
        try expect(snapshot.activeVisibleDirectoryObserverCount == 0)
        try expect(snapshot.activeVolumeObserverCount == 0)
        try expect(snapshot.activeThumbnailCount == 3)
        try await runMain { model.setActiveThumbnailCount(0) }
        let afterThumbnailCancel = try await runMain { model.snapshot.lifecycleDiagnostics }
        try expect(afterThumbnailCancel.activeThumbnailCount == 0)
        try expect(afterThumbnailCancel.timerCount == 0)
        try expect(afterThumbnailCancel.animationCount == 0)
    }

    private static func testLiveFSEventsCreationProof() async throws {
        let directory = try TemporaryDirectory()
        let diagnostics = LifecycleDiagnostics()
        let monitor = VisibleDirectoryMonitor(source: .live, diagnostics: diagnostics)

        monitor.start(root: directory.url) { _, _ in }
        monitor.stop()

        try expect(diagnostics.snapshot.visibleDirectoryObserverStartCount == 1)
        try expect(diagnostics.snapshot.activeVisibleDirectoryObserverCount == 0)
        try expect(diagnostics.snapshot.timerCount == 0)
    }

    @MainActor
    private static func makeModel(
        stored: LockedBox<[SavedLocation]>,
        bookmarkService: SecurityScopedBookmarkService,
        diagnostics: LifecycleDiagnostics = LifecycleDiagnostics(),
        directorySource: DirectoryEventSource? = nil,
        volumeSource: VolumeEventSource? = nil,
        resolveBookmark: (@Sendable (PersistedBookmark) -> BookmarkResolution)? = nil,
        metadata: (@Sendable (URL) -> ExternalLocationMetadata)? = nil,
        closeSecurityScopedURL: (@Sendable (SecurityScopedURL) -> Void)? = nil
    ) -> FileBrowserModel {
        let visibleMonitor = directorySource.map {
            VisibleDirectoryMonitor(source: $0, diagnostics: diagnostics)
        }
        let volumeObserver = volumeSource.map {
            VolumeEventObserver(source: $0, diagnostics: diagnostics)
        }
        return FileBrowserModel(
            environment: FileBrowserEnvironment(
                homeDirectory: {
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                        .appendingPathComponent(".build/test-tmp", isDirectory: true)
                },
                enumerate: { url in try await DirectoryEnumerator().enumerate(url) },
                loadSavedLocations: { stored.withValue { $0 } },
                saveSavedLocations: { locations in stored.withValue { $0 = locations } },
                makeBookmark: { try bookmarkService.makeBookmark(for: $0) },
                resolveBookmark: resolveBookmark ?? { bookmarkService.resolve($0) },
                closeSecurityScopedURL: closeSecurityScopedURL ?? { $0.close() },
                visibleDirectoryMonitor: visibleMonitor,
                volumeEventObserver: volumeObserver,
                externalLocationProbe: ExternalLocationProbe(metadata: metadata ?? { url in
                    ExternalLocationMetadata(exists: FileManager.default.fileExists(atPath: url.path))
                }),
                lifecycleDiagnostics: diagnostics
            )
        )
    }

    private static func availableResolution(url: URL) -> BookmarkResolution {
        BookmarkResolution(
            scopedURL: nil,
            originalPath: url.path,
            isStale: false,
            availability: .available,
            error: nil
        )
    }

    private static func missingResolution(path: String) -> BookmarkResolution {
        BookmarkResolution(
            scopedURL: nil,
            originalPath: path,
            isStale: false,
            availability: .unavailable,
            error: .invalidBookmark(originalPath: path)
        )
    }

    private static func unavailableLocation(
        id: UUID,
        kind: SavedLocation.ExternalKind
    ) -> SavedLocation {
        SavedLocation(
            id: id,
            displayName: "External",
            bookmark: PersistedBookmark(
                data: Data("synthetic".utf8),
                originalPath: "/Volumes/External",
                isSecurityScoped: true
            ),
            sortOrder: 0,
            availability: .unavailable,
            lastKnownExternalKind: kind
        )
    }

    private static func scopedBookmarkService(closeCount: LockedBox<Int>) -> SecurityScopedBookmarkService {
        SecurityScopedBookmarkService(
            resolveBookmark: { bookmark, isStale in
                isStale = false
                return URL(fileURLWithPath: bookmark.originalPath, isDirectory: true)
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in closeCount.withValue { $0 += 1 } },
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    private static func pumpMainActor() async {
        for _ in 0..<3 {
            await Task.yield()
            await MainActor.run {}
        }
    }

    private static func runMain<T: Sendable>(_ operation: @escaping @MainActor () throws -> T) async throws -> T {
        try await MainActor.run {
            try operation()
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
}

private final class TestDirectoryEventSource: @unchecked Sendable {
    private(set) var streams: [TestDirectoryEventStream] = []

    var source: DirectoryEventSource {
        DirectoryEventSource { [weak self] root, generation, callback in
            let stream = TestDirectoryEventStream(root: root, generation: generation, callback: callback)
            self?.streams.append(stream)
            return stream
        }
    }
}

private final class TestDirectoryEventStream: DirectoryEventStream, @unchecked Sendable {
    let root: URL
    let generation: Int
    let callback: @Sendable (Int, DirectoryEvent) -> Void
    private(set) var isStopped = false

    init(root: URL, generation: Int, callback: @escaping @Sendable (Int, DirectoryEvent) -> Void) {
        self.root = root
        self.generation = generation
        self.callback = callback
    }

    func emit(_ url: URL) {
        callback(generation, DirectoryEvent(url: url, reason: .injected))
    }

    func stop() {
        isStopped = true
    }
}

private final class TestVolumeEventSource: @unchecked Sendable {
    var stream: TestVolumeEventStream?

    var source: VolumeEventSource {
        VolumeEventSource { [weak self] callback in
            let stream = TestVolumeEventStream(callback: callback)
            self?.stream = stream
            return stream
        }
    }
}

private final class TestVolumeEventStream: VolumeEventStream, @unchecked Sendable {
    let callback: @Sendable (VolumeEvent) -> Void
    private(set) var isStopped = false

    init(callback: @escaping @Sendable (VolumeEvent) -> Void) {
        self.callback = callback
    }

    func emit(_ event: VolumeEvent) {
        callback(event)
    }

    func stop() {
        isStopped = true
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/test-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private struct ContractTestFailure: Error, CustomStringConvertible {
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
