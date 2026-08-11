import FileAccess
import FileOperations
import Foundation
import PanelFeature
import PreviewFeature

@main
struct PanelContractTests {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("browser starts at home and enumerates fixture items", testInitialHomeEnumeration),
            ("visible files default to kind sorting and support alternate columns", testFileSorting),
            ("filter query narrows visible items", testFilterQueryNarrowsVisibleItems),
            ("clearing filter restores directory items", testClearingFilterRestoresDirectoryItems),
            ("loading state brackets directory enumeration", testLoadingStateBracketsDirectoryEnumeration),
            ("activating a selected directory enters that directory", testDirectoryActivation),
            ("browser can start at a configured default location while Home remains stable", testConfiguredInitialLocation),
            ("path bar navigation opens the selected directory component", testPathBarNavigation),
            ("path bar navigation preserves the authorized saved-location root", testPathBarNavigationPreservesSavedLocationBoundary),
            ("saved locations persist rename reorder and remove", testSavedLocationManagement),
            ("favorite groups persist grouping and drag-style reordering", testFavoriteGroupManagement),
            ("saved location writes are atomic on persistence failure", testSavedLocationAtomicityOnPersistenceFailure),
            ("saved location reauthorization preserves identity and grouping", testSavedLocationReauthorization),
            ("saved location reauthorization rejects unsupported paths", testSavedLocationReauthorizationRejectsUnsupportedPath),
            ("saved location writes reject duplicate destination paths", testSavedLocationDuplicatePathRejection),
            ("saved location reauthorization rolls back persistence failure", testSavedLocationReauthorizationPersistenceFailure),
            ("unavailable saved locations remain visible without false success", testUnavailableSavedLocation),
            ("navigation errors use bounded human copy", testNavigationErrorAccessibilityCopy),
            ("unavailable saved location errors use human accessibility copy", testUnavailableErrorAccessibilityCopy),
            ("up navigation is bounded by home root", testUpNavigationStopsAtHomeRoot),
            ("saved location navigation is bounded by authorized root and closes on exit", testSavedLocationBoundaryAndScopeLifetime),
            ("saved location rejects root and protected system paths", testSavedLocationPolicyRejectsUnsupportedRoots),
            ("file item metadata classifies iCloud placeholders without downloads", testFileItemDownloadRequiredMetadata),
            ("file operation conflict default is skip through panel model", testConflictDefaultSkip),
            ("create folder routes all conflict policies through panel model", testCreateFolderConflictPolicyRouting),
            ("drop move requires allowed mask and Control modifier intent", testDropMoveRequiresExplicitIntent),
            ("partial mutation failures refresh visible directory", testPartialFailureRefreshesDirectory),
            ("quick look and teardown close preview state", testPreviewAndTeardown)
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

        print("PanelContractTests: \(tests.count) passed, 0 failed")
    }

    @MainActor
    private static func testSavedLocationAtomicityOnPersistenceFailure() async throws {
        let fixture = try TemporaryDirectory()
        let savedA = try TemporaryDirectory()
        let savedB = try TemporaryDirectory()
        let first = try savedLocation(name: "First", url: savedA.url, order: 0)
        let second = try savedLocation(name: "Second", url: savedB.url, order: 1)
        let box = LockedBox<[SavedLocation]>([first, second])
        let shouldFail = LockedBox(false)
        let model = makeModel(
            home: fixture.url,
            savedLocations: box,
            saveSavedLocations: { locations in
                if shouldFail.withValue({ $0 }) {
                    throw PanelContractFailure("forced save failure")
                }
                box.withValue { $0 = locations }
            }
        )

        await model.loadInitialState()
        shouldFail.withValue { $0 = true }

        try expectForcedSaveFailure {
            try model.addSavedLocation(url: fixture.url, displayName: "New")
        }
        try expect(model.savedLocations.map(\.displayName) == ["First", "Second"])
        try expect(box.withValue { $0.map(\.displayName) } == ["First", "Second"])

        try expectForcedSaveFailure {
            try model.renameSavedLocation(id: first.id, to: "Renamed")
        }
        try expect(model.savedLocations.map(\.displayName) == ["First", "Second"])

        try expectForcedSaveFailure {
            try model.moveSavedLocation(id: first.id, direction: 1)
        }
        try expect(model.savedLocations.map(\.displayName) == ["First", "Second"])

        try expectForcedSaveFailure {
            try model.removeSavedLocation(id: first.id)
        }
        try expect(model.savedLocations.map(\.displayName) == ["First", "Second"])
        try expect(box.withValue { $0.map(\.displayName) } == ["First", "Second"])
    }

    @MainActor
    private static func testSavedLocationReauthorization() async throws {
        let fixture = try TemporaryDirectory()
        let replacement = fixture.url.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let locationID = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let group = FavoriteGroup(id: groupID, name: "Imported", sortOrder: 0)
        let original = SavedLocation(
            id: locationID,
            displayName: "Imported Favorite",
            bookmark: PersistedBookmark(
                data: Data([0x01]),
                originalPath: "/Users/old-user/Missing",
                isSecurityScoped: true
            ),
            sortOrder: 0,
            availability: .permissionDenied,
            lastKnownExternalKind: .network,
            groupID: groupID
        )
        let replacementBookmark = PersistedBookmark(
            data: Data([0x02, 0x03]),
            originalPath: replacement.path,
            isSecurityScoped: true
        )
        let persisted = LockedBox([original])
        let model = makeModel(
            home: fixture.url,
            savedLocations: persisted,
            favoriteGroups: LockedBox([group]),
            makeBookmark: { _ in replacementBookmark }
        )
        await model.loadInitialState()

        try model.reauthorizeSavedLocation(id: locationID, url: replacement)

        let updated = try unwrap(model.savedLocations.first)
        try expect(updated.id == original.id)
        try expect(updated.displayName == original.displayName)
        try expect(updated.sortOrder == original.sortOrder)
        try expect(updated.groupID == original.groupID)
        try expect(updated.bookmark == replacementBookmark)
        try expect(updated.availability == .recovered)
        try expect(updated.lastKnownExternalKind == .local)
        try expect(persisted.withValue { $0 } == model.savedLocations)
    }

    @MainActor
    private static func testSavedLocationReauthorizationRejectsUnsupportedPath() async throws {
        let fixture = try TemporaryDirectory()
        let location = try savedLocation(name: "Existing", url: fixture.url, order: 0)
        let persisted = LockedBox([location])
        let saveCount = LockedBox(0)
        let model = makeModel(
            home: fixture.url,
            savedLocations: persisted,
            saveSavedLocations: { _ in saveCount.withValue { $0 += 1 } }
        )
        await model.loadInitialState()

        do {
            try model.reauthorizeSavedLocation(id: location.id, url: URL(fileURLWithPath: "/"))
            throw PanelContractFailure("Expected unsupported replacement path")
        } catch FileBrowserError.unsupportedSavedLocation("/") {
        }

        try expect(model.savedLocations == [location])
        try expect(persisted.withValue { $0 } == [location])
        try expect(saveCount.withValue { $0 } == 0)
    }

    @MainActor
    private static func testSavedLocationDuplicatePathRejection() async throws {
        let fixture = try TemporaryDirectory()
        let savedA = try TemporaryDirectory()
        let savedB = try TemporaryDirectory()
        let first = try savedLocation(name: "First", url: savedA.url, order: 0)
        let second = try savedLocation(name: "Second", url: savedB.url, order: 1)
        let persisted = LockedBox<[SavedLocation]>([first, second])
        let model = makeModel(home: fixture.url, savedLocations: persisted)
        await model.loadInitialState()

        var addRejected = false
        do {
            try model.addSavedLocation(url: savedA.url)
        } catch {
            addRejected = true
        }
        var reauthorizationRejected = false
        do {
            try model.reauthorizeSavedLocation(id: second.id, url: savedA.url)
        } catch {
            reauthorizationRejected = true
        }

        try expect(addRejected)
        try expect(reauthorizationRejected)
        try expect(model.savedLocations == [first, second])
        try expect(persisted.withValue { $0 } == [first, second])
    }

    @MainActor
    private static func testSavedLocationReauthorizationPersistenceFailure() async throws {
        let fixture = try TemporaryDirectory()
        let replacement = fixture.url.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        let original = try savedLocation(name: "Existing", url: fixture.url, order: 0)
        let persisted = LockedBox([original])
        let replacementBookmark = PersistedBookmark(
            data: Data([0x04]),
            originalPath: replacement.path,
            isSecurityScoped: true
        )
        let model = makeModel(
            home: fixture.url,
            savedLocations: persisted,
            saveSavedLocations: { _ in
                throw PanelContractFailure("forced reauthorization save failure")
            },
            makeBookmark: { _ in replacementBookmark }
        )
        await model.loadInitialState()

        do {
            try model.reauthorizeSavedLocation(id: original.id, url: replacement)
            throw PanelContractFailure("Expected reauthorization persistence failure")
        } catch let error as PanelContractFailure {
            try expect(error.description == "forced reauthorization save failure")
        }

        try expect(model.savedLocations == [original])
        try expect(persisted.withValue { $0 } == [original])
    }

    @MainActor
    private static func testFavoriteGroupManagement() async throws {
        let home = try TemporaryDirectory()
        let savedA = try TemporaryDirectory()
        let savedB = try TemporaryDirectory()
        let first = try savedLocation(name: "First", url: savedA.url, order: 0)
        let second = try savedLocation(name: "Second", url: savedB.url, order: 1)
        let locationBox = LockedBox<[SavedLocation]>([first, second])
        let groupBox = LockedBox<[FavoriteGroup]>([])
        let model = makeModel(
            home: home.url,
            savedLocations: locationBox,
            favoriteGroups: groupBox
        )

        await model.loadInitialState()
        let workID = try model.addFavoriteGroup(named: "Work")
        let personalID = try model.addFavoriteGroup(named: "Personal")
        try model.updateFavoriteGroupIcon(id: workID, iconName: "briefcase.fill")
        try model.moveSavedLocation(id: second.id, toGroup: workID, before: nil)
        try model.moveSavedLocation(id: first.id, toGroup: workID, before: second.id)

        try expect(model.favoriteGroups.map(\.name) == ["Work", "Personal"])
        try expect(model.favoriteSidebarItems == [
            .group(nil),
            .group(FavoriteGroup(
                id: workID,
                name: "Work",
                sortOrder: 0,
                iconName: "briefcase.fill"
            )),
            .location(model.savedLocations.first(where: { $0.id == first.id })!),
            .location(model.savedLocations.first(where: { $0.id == second.id })!),
            .group(FavoriteGroup(id: personalID, name: "Personal", sortOrder: 1))
        ])

        try model.moveSavedLocation(id: second.id, toGroup: workID, before: first.id)
        let workNames = model.favoriteSidebarItems.compactMap { item -> String? in
            guard case .location(let location) = item, location.groupID == workID else {
                return nil
            }
            return location.displayName
        }
        try expect(workNames == ["Second", "First"])

        try model.moveFavoriteGroup(id: personalID, before: workID)
        try expect(model.favoriteGroups.map(\.name) == ["Personal", "Work"])

        try model.removeFavoriteGroup(id: workID)
        try expect(model.savedLocations.allSatisfy { $0.groupID == nil })
        try expect(model.favoriteGroups.map(\.name) == ["Personal"])
        try expect(locationBox.withValue { $0.allSatisfy { $0.groupID == nil } })
        try expect(groupBox.withValue { $0.map(\.name) } == ["Personal"])
    }

    @MainActor
    private static func testInitialHomeEnumeration() async throws {
        let fixture = try TemporaryDirectory()
        try Data("alpha".utf8).write(to: fixture.url.appendingPathComponent("alpha.txt"))
        try FileManager.default.createDirectory(
            at: fixture.url.appendingPathComponent("Nested", isDirectory: true),
            withIntermediateDirectories: false
        )
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()

        try expect(
            model.snapshot.currentDirectoryURL == fixture.url.standardizedFileURL,
            "initial Home URL was not standardized"
        )
        try expect(
            model.snapshot.itemNames == ["Nested", "alpha.txt"],
            "initial Home enumeration did not return the fixture"
        )
    }

    @MainActor
    private static func testFileSorting() async throws {
        let fixture = try TemporaryDirectory()
        let older = fixture.url.appendingPathComponent("zeta.txt")
        let newer = fixture.url.appendingPathComponent("alpha.txt")
        let folder = fixture.url.appendingPathComponent("Middle", isDirectory: true)
        try Data("older".utf8).write(to: older)
        try Data("newer".utf8).write(to: newer)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newer.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 50)],
            ofItemAtPath: folder.path
        )
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        try expect(model.sortOrder == .kindThenName)
        try expect(model.items.map(\.name) == ["Middle", "alpha.txt", "zeta.txt"])

        model.setSortOrder(.nameAscending)
        try expect(model.items.map(\.name) == ["alpha.txt", "Middle", "zeta.txt"])

        model.selectFirstItem(named: "zeta.txt")
        model.setSortOrder(.nameDescending)
        try expect(model.items.map(\.name) == ["zeta.txt", "Middle", "alpha.txt"])
        try expect(model.selectedItem?.name == "zeta.txt", "sorting should preserve selection")

        model.setSortOrder(.kindThenName)
        try expect(model.items.map(\.name) == ["Middle", "alpha.txt", "zeta.txt"])

        model.setSortOrder(.modifiedNewest)
        try expect(model.items.first?.name == "alpha.txt")
        try expect(model.items.last?.name == "Middle")
    }

    @MainActor
    private static func testFilterQueryNarrowsVisibleItems() async throws {
        let fixture = try TemporaryDirectory()
        for name in ["Alpha Report.txt", "Beta Notes.txt", "Budget 2026.txt"] {
            try Data(name.utf8).write(to: fixture.url.appendingPathComponent(name))
        }
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        model.setSortOrder(.nameAscending)
        model.setFilterQuery("BUDGET")

        try expect(model.filterQuery == "BUDGET")
        try expect(model.unfilteredItemCount == 3)
        try expect(
            model.items.map(\.name) == ["Budget 2026.txt"],
            "filter should use case-insensitive filename matching"
        )
    }

    @MainActor
    private static func testClearingFilterRestoresDirectoryItems() async throws {
        let fixture = try TemporaryDirectory()
        for name in ["Alpha Report.txt", "Beta Notes.txt", "Budget 2026.txt"] {
            try Data(name.utf8).write(to: fixture.url.appendingPathComponent(name))
        }
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        model.setSortOrder(.nameAscending)
        model.setFilterQuery("notes")
        try expect(model.items.map(\.name) == ["Beta Notes.txt"])

        model.setFilterQuery("")

        try expect(model.filterQuery.isEmpty)
        try expect(
            model.items.map(\.name) == [
                "Alpha Report.txt",
                "Beta Notes.txt",
                "Budget 2026.txt"
            ],
            "clearing the filter should restore the full directory snapshot"
        )
    }

    @MainActor
    private static func testLoadingStateBracketsDirectoryEnumeration() async throws {
        let fixture = try TemporaryDirectory()
        try Data("alpha".utf8).write(to: fixture.url.appendingPathComponent("alpha.txt"))
        let gate = EnumerationGate()
        let model = makeModel(
            home: fixture.url,
            enumerate: { url in
                await gate.suspendEnumeration()
                return try await DirectoryEnumerator().enumerate(url)
            }
        )
        var transitions: [Bool] = []
        model.onLoadingStateChange = { transitions.append($0) }

        let loadTask = Task {
            await model.loadInitialState()
        }
        try await withTimeout {
            await gate.waitUntilStarted()
        }

        try expect(model.isLoading)
        try expect(transitions == [true])

        await gate.release()
        try await withTimeout {
            await loadTask.value
        }

        try expect(model.isLoading == false)
        try expect(transitions == [true, false])
        try expect(model.items.map(\.name) == ["alpha.txt"])
    }

    @MainActor
    private static func testDirectoryActivation() async throws {
        let fixture = try TemporaryDirectory()
        let nested = fixture.url.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: nested.appendingPathComponent("inside.txt"))
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        model.selectFirstItem(named: "Nested")
        let externalURL = await model.openSelectionOrEnterDirectory()

        try expect(externalURL == nil)
        try expect(model.currentDirectoryURL == nested.standardizedFileURL)
        try expect(model.items.map(\.name) == ["inside.txt"])
    }

    @MainActor
    private static func testConfiguredInitialLocation() async throws {
        let home = try TemporaryDirectory()
        let initialDirectory = try TemporaryDirectory()
        let nested = initialDirectory.url.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let configuredInitial = nested.appendingPathComponent("..", isDirectory: true)
        let model = makeModel(home: home.url, initial: configuredInitial)

        await model.loadInitialState()
        try expect(
            model.currentDirectoryURL == initialDirectory.url.standardizedFileURL,
            "configured initial location was not standardized"
        )
        model.selectFirstItem(named: "Nested")
        _ = await model.openSelectionOrEnterDirectory()
        try expect(
            model.currentDirectoryURL == nested.standardizedFileURL,
            "nested directory activation failed"
        )
        await model.navigateUp()
        try expect(
            model.currentDirectoryURL == initialDirectory.url.standardizedFileURL,
            "up navigation did not stop at configured initial root"
        )
        await model.navigateUp()
        try expect(
            model.currentDirectoryURL == initialDirectory.url.standardizedFileURL,
            "up navigation escaped configured initial root"
        )

        await model.navigateHome()
        try expect(model.currentDirectoryURL == home.url.standardizedFileURL, "Home navigation changed")
    }

    @MainActor
    private static func testPathBarNavigation() async throws {
        let home = try TemporaryDirectory()
        let parent = home.url.appendingPathComponent("Parent", isDirectory: true)
        let child = parent.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: child.appendingPathComponent("inside.txt"))
        let model = makeModel(home: home.url)

        await model.loadInitialState()
        await model.navigateToPathBarLocation(child)

        try expect(model.currentDirectoryURL == child.standardizedFileURL)
        try expect(model.items.map(\.name) == ["inside.txt"])
        await model.navigateToPathBarLocation(parent)
        try expect(model.currentDirectoryURL == parent.standardizedFileURL)
        try expect(model.items.map(\.name) == ["Child"])
    }

    @MainActor
    private static func testPathBarNavigationPreservesSavedLocationBoundary() async throws {
        let home = try TemporaryDirectory()
        let authorized = home.url.appendingPathComponent("Authorized", isDirectory: true)
        let child = authorized.appendingPathComponent("Child", isDirectory: true)
        let outside = home.url.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: child.appendingPathComponent("inside.txt"))
        try Data("outside".utf8).write(to: outside.appendingPathComponent("outside.txt"))

        let closeCount = LockedBox(0)
        let stored = LockedBox<[SavedLocation]>([])
        let model = makeModel(
            home: home.url,
            savedLocations: stored,
            bookmarkService: scopedBookmarkService(closeCount: closeCount),
            closeSecurityScopedURL: { _ in closeCount.withValue { $0 += 1 } }
        )

        await model.loadInitialState()
        try model.addSavedLocation(url: authorized, displayName: "Authorized")
        let id = try unwrap(model.savedLocations.first?.id)
        try await model.navigateToSavedLocation(id: id)
        await model.navigateToPathBarLocation(child)
        model.setFilterQuery("inside")

        await model.navigateToPathBarLocation(outside)

        try expect(
            model.currentDirectoryURL == child.standardizedFileURL,
            "path bar escaped authorized root: \(model.currentDirectoryURL.path)"
        )
        try expect(model.items.map(\.name) == ["inside.txt"])
        try expect(model.filterQuery == "inside")
        try expect(closeCount.withValue { $0 } == 0)

        await model.navigateBack()
        try expect(model.currentDirectoryURL == authorized.standardizedFileURL)
    }

    @MainActor
    private static func testSavedLocationManagement() async throws {
        let fixture = try TemporaryDirectory()
        let savedURL = fixture.url.appendingPathComponent("SavedLocation", isDirectory: true)
        try FileManager.default.createDirectory(
            at: savedURL,
            withIntermediateDirectories: false
        )
        let box = LockedBox<[SavedLocation]>([])
        let model = makeModel(home: fixture.url, savedLocations: box)
        let syntheticProtectedHome = URL(
            fileURLWithPath: "/var/tmp/PathShelf-Configured-Home",
            isDirectory: true
        )
        try NavigationAccessPolicy(
            homeRoot: syntheticProtectedHome,
            userHomeRoot: URL(fileURLWithPath: "/Users/PathShelf-Unrelated", isDirectory: true)
        ).validateSavedLocation(
            syntheticProtectedHome.appendingPathComponent("SavedLocation", isDirectory: true)
        )

        await model.loadInitialState()
        try model.addSavedLocation(url: savedURL, displayName: "Saved")
        let id = try unwrap(model.savedLocations.first?.id)
        try model.renameSavedLocation(id: id, to: "Renamed")
        try model.moveSavedLocation(id: id, direction: 1)

        try expect(box.withValue { $0.map(\.displayName) } == ["Renamed"])
        try model.removeSavedLocation(id: id)
        try expect(box.withValue { $0.isEmpty })
    }

    @MainActor
    private static func testUnavailableSavedLocation() async throws {
        let fixture = try TemporaryDirectory()
        let missingPath = "/definitely/missing/panel-location"
        let location = SavedLocation(
            displayName: "Missing",
            bookmark: PersistedBookmark(
                data: Data("missing".utf8),
                originalPath: missingPath,
                isSecurityScoped: true
            ),
            sortOrder: 0
        )
        let box = LockedBox<[SavedLocation]>([location])
        let model = makeModel(
            home: fixture.url,
            savedLocations: box,
            resolveBookmark: { bookmark in
                BookmarkResolution(
                    scopedURL: nil,
                    originalPath: bookmark.originalPath,
                    isStale: false,
                    availability: .unavailable,
                    error: .invalidBookmark(originalPath: bookmark.originalPath)
                )
            }
        )

        await model.loadInitialState()
        do {
            try await model.navigateToSavedLocation(id: location.id)
            throw PanelContractFailure("Expected unavailable location to throw")
        } catch FileBrowserError.selectedLocationUnavailable(.unavailable, missingPath) {
        }

        try expect(model.savedLocations.first?.displayName == "Missing")
        try expect(model.savedLocations.first?.availability == .unavailable)
        try expect(model.snapshot.lastErrorMessage?.contains("unavailable") == true)
    }

    private static func testUnavailableErrorAccessibilityCopy() throws {
        let error = FileBrowserError.selectedLocationUnavailable(
            .permissionDenied,
            "/Users/example/Unavailable"
        )
        try expect(
            error.description
                == "Saved location needs folder access on this Mac: /Users/example/Unavailable"
        )
    }

    @MainActor
    private static func testNavigationErrorAccessibilityCopy() async throws {
        let fixture = try TemporaryDirectory()
        let model = makeModel(
            home: fixture.url,
            enumerate: { _ in
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoPermissionError,
                    userInfo: [NSFilePathErrorKey: "/private/example"]
                )
            }
        )

        await model.loadInitialState()
        guard let message = model.snapshot.lastErrorMessage else {
            throw PanelContractFailure("Expected a bounded navigation error")
        }
        try expect(message.contains("NSCocoaErrorDomain") == false)
        try expect(message.contains("UserInfo") == false)
        try expect(message.contains("/private/example") == false)
    }

    @MainActor
    private static func testUpNavigationStopsAtHomeRoot() async throws {
        let fixture = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: fixture.url.appendingPathComponent("Child", isDirectory: true),
            withIntermediateDirectories: false
        )
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        model.selectFirstItem(named: "Child")
        _ = await model.openSelectionOrEnterDirectory()
        try expect(model.currentDirectoryURL.lastPathComponent == "Child")

        await model.navigateUp()
        try expect(model.currentDirectoryURL == fixture.url.standardizedFileURL)
        await model.navigateUp()
        try expect(model.currentDirectoryURL == fixture.url.standardizedFileURL)
    }

    @MainActor
    private static func testSavedLocationBoundaryAndScopeLifetime() async throws {
        let home = try TemporaryDirectory()
        let savedURL = home.url.appendingPathComponent("ScopedSavedLocation", isDirectory: true)
        try FileManager.default.createDirectory(
            at: savedURL.appendingPathComponent("Nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        let closeCount = LockedBox(0)
        let bookmarkService = scopedBookmarkService(closeCount: closeCount)
        let stored = LockedBox<[SavedLocation]>([])
        let model = makeModel(
            home: home.url,
            savedLocations: stored,
            bookmarkService: bookmarkService,
            closeSecurityScopedURL: { _ in closeCount.withValue { $0 += 1 } }
        )

        await model.loadInitialState()
        try model.addSavedLocation(url: savedURL, displayName: "External")
        let id = try unwrap(model.savedLocations.first?.id)
        try await model.navigateToSavedLocation(id: id)
        try expect(
            model.currentDirectoryURL == savedURL.standardizedFileURL,
            "did not navigate to saved root: \(model.currentDirectoryURL.path)"
        )
        model.selectFirstItem(named: "Nested")
        _ = await model.openSelectionOrEnterDirectory()
        try expect(model.currentDirectoryURL.lastPathComponent == "Nested", "did not enter nested: \(model.currentDirectoryURL.path), items \(model.items.map(\.name))")

        await model.navigateUp()
        try expect(
            model.currentDirectoryURL == savedURL.standardizedFileURL,
            "up did not return to saved root: \(model.currentDirectoryURL.path)"
        )
        await model.navigateUp()
        try expect(
            model.currentDirectoryURL == savedURL.standardizedFileURL,
            "up escaped saved root: \(model.currentDirectoryURL.path)"
        )
        try expect(closeCount.withValue { $0 } == 0, "scope closed while still inside saved root")

        await model.navigateHome()
        try expect(
            model.currentDirectoryURL == home.url.standardizedFileURL,
            "home did not navigate to home: \(model.currentDirectoryURL.path)"
        )
        try expect(closeCount.withValue { $0 } == 1, "scope close count was \(closeCount.withValue { $0 })")

        await model.navigateBack()
        try expect(
            model.currentDirectoryURL == savedURL.standardizedFileURL,
            "back did not return to saved root: \(model.currentDirectoryURL.path)"
        )
        try expect(model.items.map(\.name) == ["Nested"])
        try expect(closeCount.withValue { $0 } == 1, "back did not keep reacquired scope open")

        model.teardown()
        try expect(closeCount.withValue { $0 } == 2, "teardown did not close reacquired scope")
    }

    @MainActor
    private static func testSavedLocationPolicyRejectsUnsupportedRoots() async throws {
        let home = try TemporaryDirectory()
        let stored = LockedBox<[SavedLocation]>([])
        let model = makeModel(
            home: home.url,
            savedLocations: stored,
            makeBookmark: { url in
                PersistedBookmark(data: Data(url.path.utf8), originalPath: url.path, isSecurityScoped: true)
            }
        )

        await model.loadInitialState()
        do {
            try model.addSavedLocation(url: URL(fileURLWithPath: "/", isDirectory: true), displayName: "Root")
            throw PanelContractFailure("Expected root save rejection")
        } catch FileBrowserError.unsupportedSavedLocation("/") {
        }
        do {
            try model.addSavedLocation(url: URL(fileURLWithPath: "/System/Library", isDirectory: true), displayName: "System")
            throw PanelContractFailure("Expected system save rejection")
        } catch FileBrowserError.unsupportedSavedLocation("/System/Library") {
        }

        try model.addSavedLocation(
            url: URL(fileURLWithPath: "/Volumes/External", isDirectory: true),
            displayName: "External"
        )
        try expect(stored.withValue { $0.map(\.displayName) } == ["External"])
    }

    private static func testFileItemDownloadRequiredMetadata() throws {
        let item = FileItem(
            url: URL(fileURLWithPath: "/Users/example/iCloud/placeholder.txt"),
            name: "placeholder.txt",
            kind: .file,
            byteSize: nil,
            contentModificationDate: nil,
            creationDate: nil,
            isHidden: false,
            localAvailability: FileItem.LocalAvailabilityClassifier.classify(
                isUbiquitousItem: true,
                downloadingState: .notDownloaded
            )
        )

        try expect(item.localAvailability == .downloadRequired)
        try expect(
            FileItem.LocalAvailabilityClassifier.classify(
                isUbiquitousItem: true,
                downloadingState: .current
            ) == .local
        )
    }

    @MainActor
    private static func testConflictDefaultSkip() async throws {
        let fixture = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: fixture.url.appendingPathComponent("Existing", isDirectory: true),
            withIntermediateDirectories: false
        )
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        let outcome = await model.createFolder(named: "Existing")

        try expect(outcome.status == .skipped)
        try expect(outcome.conflictPolicy == .skip)
        try expect(model.snapshot.lastOperationStatus == .skipped)
    }

    @MainActor
    private static func testCreateFolderConflictPolicyRouting() async throws {
        let fixture = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: fixture.url.appendingPathComponent("Existing", isDirectory: true),
            withIntermediateDirectories: false
        )
        let model = makeModel(home: fixture.url)

        await model.loadInitialState()
        let skip = await model.createFolder(named: "Existing", conflictPolicy: .skip)
        let keepBoth = await model.createFolder(named: "Existing", conflictPolicy: .keepBoth)
        let replace = await model.createFolder(named: "Existing", conflictPolicy: .replace)

        try expect(skip.status == .skipped)
        try expect(skip.conflictPolicy == .skip)
        try expect(keepBoth.status == .success)
        try expect(keepBoth.conflictPolicy == .keepBoth)
        try expect(keepBoth.destinationURL?.lastPathComponent == "Existing copy")
        try expect(replace.conflictPolicy == .replace)
        try expect(replace.status == .success || replace.status == .partiallyFailed)
    }

    private static func testDropMoveRequiresExplicitIntent() throws {
        try expect(
            DropOperationResolver.shouldMove(DropOperationIntent(allowsMove: true, explicitMove: false)) == false
        )
        try expect(
            DropOperationResolver.shouldMove(DropOperationIntent(allowsMove: false, explicitMove: true)) == false
        )
        try expect(
            DropOperationResolver.shouldMove(DropOperationIntent(allowsMove: true, explicitMove: true)) == true
        )
    }

    @MainActor
    private static func testPartialFailureRefreshesDirectory() async throws {
        let fixture = try TemporaryDirectory()
        let sourceDirectory = try TemporaryDirectory()
        let source = sourceDirectory.url.appendingPathComponent("source.txt")
        let destination = fixture.url.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)
        let enumerateCount = LockedBox(0)
        let fileSystem = FileOperationFileSystem(
            fileExists: { url in FileManager.default.fileExists(atPath: url.path) },
            createDirectory: { url in try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) },
            copyItem: { _, _ in throw PanelContractFailure("copy failed after trash") },
            moveItem: { _, _ in },
            trashItem: { url in
                URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
            }
        )
        let model = makeModel(
            home: fixture.url,
            enumerate: { url in
                enumerateCount.withValue { $0 += 1 }
                return try await DirectoryEnumerator().enumerate(url)
            },
            fileOperationService: FileOperationService(fileSystem: fileSystem)
        )

        await model.loadInitialState()
        let before = enumerateCount.withValue { $0 }
        let outcome = await model.performFileOperation(
            FileOperationRequest(
                action: .copy,
                sourceURL: source,
                destinationDirectoryURL: fixture.url,
                conflictPolicy: .replace
            )
        )

        try expect(outcome.status == .partiallyFailed, "outcome was \(outcome.status), error \(String(describing: outcome.error))")
        try expect(enumerateCount.withValue { $0 } > before, "enumeration did not refresh after partial failure")
        try expect(model.snapshot.lastOperationStatus == .partiallyFailed, "snapshot status was \(String(describing: model.snapshot.lastOperationStatus))")
        try expect(model.snapshot.lastErrorMessage?.contains("Replace partially failed") == true, "message was \(model.snapshot.lastErrorMessage ?? "nil")")
    }

    @MainActor
    private static func testPreviewAndTeardown() async throws {
        let fixture = try TemporaryDirectory()
        let file = fixture.url.appendingPathComponent("alpha.txt")
        try Data("alpha".utf8).write(to: file)
        let preview = QuickLookPreviewController()
        let model = makeModel(home: fixture.url, previewController: preview)

        await model.loadInitialState()
        model.selectFirstItem(named: "alpha.txt")
        model.presentQuickLookForSelection()
        if case .presenting(let item) = preview.state {
            try expect(item.url.lastPathComponent == file.lastPathComponent)
        } else {
            throw PanelContractFailure("Expected preview to present selected file")
        }

        model.teardown()
        try expect(preview.state == .closed)
        try expect(model.snapshot.teardownCount == 1)
        try expect(model.snapshot.selectedItemName == nil)
    }

    @MainActor
    private static func makeModel(
        home: URL,
        initial: URL? = nil,
        savedLocations: LockedBox<[SavedLocation]> = LockedBox([]),
        favoriteGroups: LockedBox<[FavoriteGroup]> = LockedBox([]),
        enumerate: (@Sendable (URL) async throws -> DirectoryEnumerationResult)? = nil,
        saveSavedLocations: (@Sendable ([SavedLocation]) throws -> Void)? = nil,
        makeBookmark: (@Sendable (URL) throws -> PersistedBookmark)? = nil,
        resolveBookmark: (@Sendable (PersistedBookmark) -> BookmarkResolution)? = nil,
        bookmarkService: SecurityScopedBookmarkService? = nil,
        closeSecurityScopedURL: (@Sendable (SecurityScopedURL) -> Void)? = nil,
        fileOperationService: FileOperationService = FileOperationService(),
        previewController: QuickLookPreviewController? = nil
    ) -> FileBrowserModel {
        let bookmarkService = bookmarkService ?? SecurityScopedBookmarkService()
        let initialURL = initial ?? home
        return FileBrowserModel(
            environment: FileBrowserEnvironment(
                homeDirectory: { home },
                initialDirectory: { initialURL },
                enumerate: enumerate ?? { url in try await DirectoryEnumerator().enumerate(url) },
                loadSavedLocations: { savedLocations.withValue { $0 } },
                saveSavedLocations: saveSavedLocations ?? { locations in savedLocations.withValue { $0 = locations } },
                loadFavoriteGroups: { favoriteGroups.withValue { $0 } },
                saveFavoriteGroups: { groups in favoriteGroups.withValue { $0 = groups } },
                makeBookmark: makeBookmark ?? { url in try bookmarkService.makeBookmark(for: url) },
                resolveBookmark: resolveBookmark ?? { bookmarkService.resolve($0) },
                fileOperationService: fileOperationService,
                previewController: previewController,
                closeSecurityScopedURL: closeSecurityScopedURL ?? { $0.close() }
            )
        )
    }

    private static func savedLocation(name: String, url: URL, order: Int) throws -> SavedLocation {
        let bookmark = try SecurityScopedBookmarkService().makeBookmark(for: url)
        return SavedLocation(displayName: name, bookmark: bookmark, sortOrder: order)
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

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

private actor EnumerationGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        guard started == false else {
            return
        }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func suspendEnumeration() async {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct PanelContractFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Expectation failed") throws {
    guard condition() else {
        throw PanelContractFailure(message)
    }
}

private func expectForcedSaveFailure(_ operation: () throws -> Void) throws {
    do {
        try operation()
        throw PanelContractFailure("Expected forced save failure")
    } catch let error as PanelContractFailure {
        try expect(error.description == "forced save failure", "Expected forced save failure, got \(error)")
    }
}

private func unwrap<Value>(_ value: Value?) throws -> Value {
    guard let value else {
        throw PanelContractFailure("Expected non-nil value")
    }
    return value
}

private func withTimeout<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(2))
            throw PanelContractFailure("Timed out waiting for async contract signal")
        }
        guard let value = try await group.next() else {
            throw PanelContractFailure("Async contract signal produced no result")
        }
        group.cancelAll()
        return value
    }
}
