import FileAccess
import Foundation
import PanelFeature
import SettingsFeature

@main
struct ContractTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("bookmark round-trip preserves stable sort order", testBookmarkRoundTrip),
            ("missing bookmark file loads as empty list", testMissingBookmarksLoadEmpty),
            ("favorite group round-trip preserves explicit order", testFavoriteGroupRoundTrip),
            ("legacy favorite groups decode with the default icon", testLegacyFavoriteGroupIconCompatibility),
            ("legacy favorites without a group decode into Default Group", testLegacyFavoriteGroupCompatibility),
            ("saved location availability uses human accessibility copy", testAvailabilityAccessibilityCopy),
            ("default settings prefer cursor-adjacent placement", testDefaultSettings),
            ("settings round-trip through JSON storage", testSettingsRoundTrip),
            ("settings transfer manifest validates relationships", testSettingsTransferRelationshipValidation),
            ("settings transfer manifest validates deterministic sort orders", testSettingsTransferSortOrderValidation),
            ("settings transfer manifest round-trips deterministically", testSettingsTransferRoundTrip),
            ("settings transfer encodes shortcut modifiers canonically", testSettingsTransferModifierEncoding),
            ("settings transfer preserves case-distinct Favorite paths", testSettingsTransferCaseDistinctPaths),
            ("settings transfer manifest rejects incompatible documents", testSettingsTransferValidation),
            ("settings transfer enforces resource limits", testSettingsTransferResourceLimits),
            ("settings transfer rejects protected default locations", testSettingsTransferProtectedDefaultLocation),
            ("settings transfer rejects unresolved protected Favorites", testSettingsTransferUnresolvedProtectedFavorite),
            ("settings transfer rejects escaped bookmark destinations", testSettingsTransferEscapedBookmark),
            ("settings transfer rejects regular-file bookmark destinations", testSettingsTransferRegularFileBookmark),
            ("settings transfer rejects canonical duplicate Favorites", testSettingsTransferCanonicalDuplicateFavorite),
            ("settings transfer import replaces all stores", testSettingsTransferImport),
            ("settings transfer preview makes no writes", testSettingsTransferPreview),
            ("settings transfer import rolls back all stores", testSettingsTransferImportRollback),
            ("settings transfer import rejects shortcut conflicts before writes", testSettingsTransferShortcutConflict),
            ("settings transfer import rejects unavailable launch-at-login", testSettingsTransferLaunchUnavailable),
            ("settings transfer import surfaces rollback failure", testSettingsTransferRollbackFailure),
            ("settings transfer rollback restores disabled launch runtime", testSettingsTransferRollbackRestoresDisabledLaunchRuntime),
            ("settings transfer rollback restores enabled launch runtime", testSettingsTransferRollbackRestoresEnabledLaunchRuntime),
            ("browser display preferences round-trip and default safely", testBrowserDisplayPreferences),
            ("missing settings file throws explicit error", testMissingSettingsIsExplicit),
            ("default shortcut contains Command or Control", testDefaultShortcutValidation),
            ("invalid shortcut rejects Option and Shift without Command or Control", testInvalidShortcutValidation),
            ("Carbon OSStatus values map to stable hotkey errors", testCarbonHotKeyErrorMapping),
            ("cursor-adjacent placement clamps to visible frame", testCursorAdjacentPlacement),
            ("top-center placement uses active display visible frame", testTopCenterPlacement),
            ("home navigation starts at current user home directory", testHomeDirectoryProvider),
            ("security-scoped bookmark resolves to an accessible folder", testSecurityScopedBookmarkResolution),
            ("invalid bookmark reports unavailable instead of success", testInvalidBookmarkResolution),
            ("security-scoped bookmark start failure reports permission denied", testSecurityScopedStartFailureIsPermissionDenied),
            ("directory enumeration returns metadata off the main thread", testDirectoryEnumeration),
            ("directory enumeration hides dotfiles unless enabled", testHiddenFileEnumeration),
            ("file coordinator reads file data off the main thread", testCoordinatedRead),
            ("file coordinator missing accessor result fails explicitly", testCoordinatedReadMissingAccessorResult),
            ("old settings JSON without shortcut decodes with default shortcut", testOldSettingsJSONCompatibility),
            ("settings persist panel placement and shortcut binding", testSettingsPersistPlacementAndShortcut),
            ("invalid hotkey candidate is not saved by invocation controller", testInvalidHotKeyCandidateNotSaved),
            ("startup shortcut registration failure does not silently register default", testStartupShortcutFailureDoesNotRegisterDefault),
            ("startup shortcut registration failure preserves previous active binding", testStartupShortcutFailurePreservesPreviousActiveBinding),
            ("startup shortcut registration success uses saved binding", testStartupShortcutSuccessUsesSavedBinding),
            ("shortcut save failure rolls back to previous binding", testShortcutSaveFailureRollsBack),
            ("shortcut save and rollback failure unregisters runtime binding", testShortcutSaveAndRollbackFailureUnregisters),
            ("successful shortcut commit persists and updates memory", testSuccessfulShortcutCommitPersists),
            ("panel placement save failure leaves memory and disk unchanged", testPlacementSaveFailureNoMemoryDivergence),
            ("browser preferences persist atomically through invocation controller", testBrowserPreferencesPersist),
            ("launch-at-login success persists and updates memory", testLaunchAtLoginSuccessPersists),
            ("launch-at-login runtime failure does not persist", testLaunchAtLoginRuntimeFailureDoesNotPersist),
            ("launch-at-login save failure rolls back runtime", testLaunchAtLoginSaveFailureRollsBack),
            ("launch-at-login save and rollback failure reports distinct error", testLaunchAtLoginSaveAndRollbackFailure),
            ("launch-at-login unchanged state is a no-op and drift reconciles", testLaunchAtLoginUnchangedNoOps),
            ("launch-at-login contradictory status does not persist", testLaunchAtLoginContradictoryStatusDoesNotPersist),
            ("shortcut key choices map supported keys and fallback", testShortcutKeyChoiceMapping),
            ("settings status formatter covers launch-at-login states", testSettingsStatusFormatter),
            ("panel placement calculation is deterministic for one invocation input", testPlacementCalculationDeterministic)
        ]

        for (index, test) in tests.enumerated() {
            do {
                try test.1()
                print("ok \(index + 1) - \(test.0)")
            } catch {
                print("not ok \(index + 1) - \(test.0)")
                print("  \(error)")
                exit(1)
            }
        }

        print("ContractTests: \(tests.count) passed, 0 failed")
    }

    private static func testBookmarkRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let store = JSONBookmarkStore(
            storageURL: directory.url.appendingPathComponent("bookmarks.json")
        )
        let second = SavedLocation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Second",
            bookmark: PersistedBookmark(
                data: Data("second".utf8),
                originalPath: "/Users/example/Second",
                isSecurityScoped: true
            ),
            sortOrder: 2
        )
        let first = SavedLocation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "First",
            bookmark: PersistedBookmark(
                data: Data("first".utf8),
                originalPath: "/Users/example/First",
                isSecurityScoped: true
            ),
            sortOrder: 1,
            availability: .staleBookmark
        )

        try store.saveSavedLocations([second, first])

        try expect(try store.loadSavedLocations() == [first, second])
    }

    private static func testMissingBookmarksLoadEmpty() throws {
        let directory = try TemporaryDirectory()
        let store = JSONBookmarkStore(
            storageURL: directory.url.appendingPathComponent("missing.json")
        )

        try expect(try store.loadSavedLocations().isEmpty)
    }

    private static func testFavoriteGroupRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let store = JSONFavoriteGroupStore(
            storageURL: directory.url.appendingPathComponent("favorite-groups.json")
        )
        let second = FavoriteGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Second",
            sortOrder: 1
        )
        let first = FavoriteGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "First",
            sortOrder: 0,
            iconName: "briefcase.fill"
        )

        try store.saveFavoriteGroups([second, first])

        try expect(try store.loadFavoriteGroups() == [first, second])
    }

    private static func testLegacyFavoriteGroupIconCompatibility() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "sortOrder": 0
        }
        """

        let decoded = try JSONDecoder().decode(FavoriteGroup.self, from: Data(json.utf8))

        try expect(decoded.iconName == nil)
    }

    private static func testLegacyFavoriteGroupCompatibility() throws {
        let json = """
        {
          "availability": "available",
          "bookmark": {
            "data": "bGVnYWN5",
            "isSecurityScoped": true,
            "originalPath": "/Users/example/Legacy"
          },
          "displayName": "Legacy",
          "id": "00000000-0000-0000-0000-000000000001",
          "sortOrder": 0
        }
        """

        let decoded = try JSONDecoder().decode(SavedLocation.self, from: Data(json.utf8))

        try expect(decoded.groupID == nil)
    }

    private static func testAvailabilityAccessibilityCopy() throws {
        try expect(
            SavedLocation.Availability.permissionDenied.accessibilityDescription
                == "Needs folder access on this Mac"
        )
        try expect(
            SavedLocation.Availability.staleBookmark.accessibilityDescription
                == "Needs folder access on this Mac"
        )
        try expect(
            SavedLocation.Availability.networkUnavailable.accessibilityDescription
                == "Network location unavailable"
        )
        try expect(
            SavedLocation.Availability.iCloudPlaceholder.accessibilityDescription
                == "Available in iCloud"
        )
    }

    private static func testDefaultSettings() throws {
        try expect(AppSettings.default.panelPlacement.mode == .cursorAdjacent)
        try expect(AppSettings.default.launchAtLogin == false)
    }

    private static func testSettingsRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let store = SettingsStore(
            storageURL: directory.url.appendingPathComponent("settings.json")
        )
        let settings = AppSettings(
            panelPlacement: PanelPlacementPreference(mode: .activeDisplayTopCenter),
            launchAtLogin: true,
            showHiddenFiles: true,
            visibleDetailColumns: [.modified, .kind, .size],
            defaultLocationPath: "/Users/example/Projects"
        )

        try store.save(settings)

        try expect(try store.load() == settings)
    }

    private static func testSettingsTransferRoundTrip() throws {
        let codec = SettingsTransferCodec()
        let settings = AppSettings(
            panelPlacement: PanelPlacementPreference(mode: .activeDisplayTopCenter),
            shortcut: ShortcutBinding(keyCode: 12, modifiers: [.control]),
            launchAtLogin: true,
            showHiddenFiles: true,
            visibleDetailColumns: [.modified, .kind, .size],
            defaultLocationPath: "/Users/example/Projects"
        )
        let group = FavoriteGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "Work",
            sortOrder: 0,
            iconName: "folder"
        )
        let location = SavedLocation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            displayName: "Projects",
            bookmark: PersistedBookmark(
                data: Data([0x01, 0x02, 0x03]),
                originalPath: "/Users/example/Projects",
                isSecurityScoped: true
            ),
            sortOrder: 0,
            availability: .permissionDenied,
            lastKnownExternalKind: .local,
            groupID: group.id
        )
        let manifest = try codec.makeManifest(
            settings: settings,
            favoriteGroups: [group],
            savedLocations: [location],
            producerVersion: "0.1.0"
        )
        let data = try codec.encode(manifest)
        let decoded = try codec.decode(data)
        let reversed = SettingsTransferManifest(
            producerVersion: manifest.producerVersion,
            settings: manifest.settings,
            favoriteGroups: Array(manifest.favoriteGroups.reversed()),
            savedLocations: Array(manifest.savedLocations.reversed())
        )

        try expect(decoded == manifest)
        try expect(decoded.settings.appSettings == settings)
        try expect(try codec.encode(reversed) == data)
        try expect(String(decoding: data, as: UTF8.self).contains("\"availability\"") == false)
    }

    private static func testSettingsTransferModifierEncoding() throws {
        let codec = SettingsTransferCodec()
        let settings = AppSettings(
            shortcut: ShortcutBinding(
                keyCode: 12,
                modifiers: Set(ShortcutBinding.Modifier.allCases)
            )
        )
        let manifest = try codec.makeManifest(
            settings: settings,
            favoriteGroups: [],
            savedLocations: [],
            producerVersion: "0.1.0"
        )
        let data = try codec.encode(manifest)
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let encodedSettings = document?["settings"] as? [String: Any]
        let encodedShortcut = encodedSettings?["shortcut"] as? [String: Any]
        let encodedModifiers = encodedShortcut?["modifiers"] as? [String]

        try expect(
            encodedModifiers == ShortcutBinding.Modifier.allCases.map(\.rawValue)
        )
    }

    private static func testSettingsTransferRelationshipValidation() throws {
        let codec = SettingsTransferCodec()
        let settings = SettingsTransferSettings(settings: .default)
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let locationID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let group = FavoriteGroup(id: groupID, name: "Work", sortOrder: 0)
        let location = TransferSavedLocation(
            location: SavedLocation(
                id: locationID,
                displayName: "Projects",
                bookmark: PersistedBookmark(
                    data: Data([0x01]),
                    originalPath: "/Users/example/Projects",
                    isSecurityScoped: true
                ),
                sortOrder: 0,
                groupID: groupID
            )
        )

        do {
            _ = try codec.encode(
                SettingsTransferManifest(
                    producerVersion: "0.1.0",
                    settings: settings,
                    favoriteGroups: [FavoriteGroup(id: groupID, name: " ", sortOrder: 0)],
                    savedLocations: []
                )
            )
            throw ContractTestFailure("Expected empty group name to fail")
        } catch SettingsTransferError.emptyGroupName(groupID) {
        }

        do {
            _ = try codec.encode(
                SettingsTransferManifest(
                    producerVersion: "0.1.0",
                    settings: settings,
                    favoriteGroups: [group, group],
                    savedLocations: []
                )
            )
            throw ContractTestFailure("Expected duplicate group ID to fail")
        } catch SettingsTransferError.duplicateGroupID(groupID) {
        }

        do {
            _ = try codec.encode(
                SettingsTransferManifest(
                    producerVersion: "0.1.0",
                    settings: settings,
                    favoriteGroups: [group],
                    savedLocations: [location, location]
                )
            )
            throw ContractTestFailure("Expected duplicate location ID to fail")
        } catch SettingsTransferError.duplicateLocationID(locationID) {
        }

        var duplicatePath = location
        duplicatePath.id = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        duplicatePath.bookmark.originalPath = "/Users/example/Projects/../Projects"
        do {
            _ = try codec.encode(
                SettingsTransferManifest(
                    producerVersion: "0.1.0",
                    settings: settings,
                    favoriteGroups: [group],
                    savedLocations: [location, duplicatePath]
                )
            )
            throw ContractTestFailure("Expected duplicate normalized path to fail")
        } catch SettingsTransferError.duplicatePath("/Users/example/Projects") {
        }

        var dangling = location
        let missingGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        dangling.groupID = missingGroupID
        do {
            _ = try codec.encode(
                SettingsTransferManifest(
                    producerVersion: "0.1.0",
                    settings: settings,
                    favoriteGroups: [group],
                    savedLocations: [dangling]
                )
            )
            throw ContractTestFailure("Expected dangling group reference to fail")
        } catch SettingsTransferError.danglingGroupID(missingGroupID) {
        }
    }

    private static func testSettingsTransferSortOrderValidation() throws {
        let fixture = try transferFixture(settings: .default)
        let codec = SettingsTransferCodec()
        func isRejected(
            groups: [FavoriteGroup],
            locations: [SavedLocation]
        ) -> Bool {
            do {
                _ = try codec.makeManifest(
                    settings: .default,
                    favoriteGroups: groups,
                    savedLocations: locations,
                    producerVersion: "0.1.0"
                )
                return false
            } catch {
                return true
            }
        }

        var negativeGroups = fixture.groups
        negativeGroups[0].sortOrder = -1
        try expect(isRejected(groups: negativeGroups, locations: fixture.locations))

        var secondGroup = fixture.groups[0]
        secondGroup.id = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        try expect(
            isRejected(
                groups: fixture.groups + [secondGroup],
                locations: fixture.locations
            )
        )

        var negativeLocations = fixture.locations
        negativeLocations[0].sortOrder = -1
        try expect(isRejected(groups: fixture.groups, locations: negativeLocations))

        var duplicateLocation = fixture.locations[0]
        duplicateLocation.id = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        duplicateLocation.bookmark.originalPath = "/Users/example/Other"
        try expect(
            isRejected(
                groups: fixture.groups,
                locations: fixture.locations + [duplicateLocation]
            )
        )

        secondGroup.sortOrder = fixture.groups[0].sortOrder + 1
        duplicateLocation.groupID = secondGroup.id
        _ = try codec.makeManifest(
            settings: .default,
            favoriteGroups: fixture.groups + [secondGroup],
            savedLocations: fixture.locations + [duplicateLocation],
            producerVersion: "0.1.0"
        )
    }

    private static func testSettingsTransferValidation() throws {
        let codec = SettingsTransferCodec()

        do {
            _ = try codec.decode(Data("not-json".utf8))
            throw ContractTestFailure("Expected malformed transfer JSON to fail")
        } catch SettingsTransferError.invalidDocument {
        }

        let unsupported = Data("""
        {
          "format": "\(SettingsTransferManifest.formatIdentifier)",
          "schemaVersion": 2,
          "producerVersion": "0.1.0",
          "settings": {},
          "favoriteGroups": [],
          "savedLocations": []
        }
        """.utf8)
        do {
            _ = try codec.decode(unsupported)
            throw ContractTestFailure("Expected unsupported transfer schema to fail")
        } catch SettingsTransferError.unsupportedVersion(2) {
        }
    }

    private static func testSettingsTransferResourceLimits() throws {
        let codec = SettingsTransferCodec()
        let fixture = try transferFixture(settings: .default)

        var oversizedDocument = fixture.data
        oversizedDocument.append(
            Data(repeating: 0x20, count: 16 * 1_024 * 1_024)
        )
        var oversizedDocumentRejected = false
        do {
            _ = try codec.decode(oversizedDocument)
        } catch {
            oversizedDocumentRejected = true
        }
        try expect(oversizedDocumentRejected)

        let tooManyGroups = (0...256).map {
            FavoriteGroup(name: "Group \($0)", sortOrder: $0)
        }
        var groupCountRejected = false
        do {
            _ = try codec.makeManifest(
                settings: .default,
                favoriteGroups: tooManyGroups,
                savedLocations: [],
                producerVersion: "0.1.0"
            )
        } catch {
            groupCountRejected = true
        }
        try expect(groupCountRejected)

        var oversizedBookmark = fixture.locations[0]
        oversizedBookmark.bookmark.data = Data(
            repeating: 0x01,
            count: 1_024 * 1_024 + 1
        )
        var bookmarkRejected = false
        do {
            _ = try codec.makeManifest(
                settings: .default,
                favoriteGroups: fixture.groups,
                savedLocations: [oversizedBookmark],
                producerVersion: "0.1.0"
            )
        } catch {
            bookmarkRejected = true
        }
        try expect(bookmarkRejected)

        var oversizedName = fixture.locations[0]
        oversizedName.displayName = String(repeating: "a", count: 4_097)
        var textRejected = false
        do {
            _ = try codec.makeManifest(
                settings: .default,
                favoriteGroups: fixture.groups,
                savedLocations: [oversizedName],
                producerVersion: "0.1.0"
            )
        } catch {
            textRejected = true
        }
        try expect(textRejected)
    }

    private static func testSettingsTransferProtectedDefaultLocation() throws {
        let path = "/System/PathShelf-Missing"
        let candidate = AppSettings(defaultLocationPath: path)
        let fixture = try transferFixture(settings: candidate)
        let settingsStore = FakeSettingsStore(initial: .default)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: .default)
        )
        invocation.loadAndRegister()
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: FakeBookmarkStore(initial: []),
            favoriteGroupStore: FakeFavoriteGroupStore(initial: [])
        )

        try expect(
            coordinator.preview(fixture.data)
                == .failure(.transfer(.invalidPath(path)))
        )
    }

    private static func testSettingsTransferUnresolvedProtectedFavorite() throws {
        let fixture = try transferFixture(settings: .default)
        let path = "/System/PathShelf-Missing"
        var location = fixture.locations[0]
        location.bookmark.originalPath = path
        let data = try SettingsTransferCodec().encode(
            SettingsTransferCodec().makeManifest(
                settings: .default,
                favoriteGroups: fixture.groups,
                savedLocations: [location],
                producerVersion: "0.1.0"
            )
        )
        let settingsStore = FakeSettingsStore(initial: .default)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: .default)
        )
        invocation.loadAndRegister()
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: FakeBookmarkStore(initial: []),
            favoriteGroupStore: FakeFavoriteGroupStore(initial: [])
        )

        try expect(
            coordinator.preview(data)
                == .failure(.transfer(.invalidPath(path)))
        )
    }

    private static func testSettingsTransferEscapedBookmark() throws {
        let fixture = try transferFixture(settings: .default)
        var location = fixture.locations[0]
        location.bookmark.originalPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Imported", isDirectory: true)
            .path
        let data = try SettingsTransferCodec().encode(
            SettingsTransferCodec().makeManifest(
                settings: .default,
                favoriteGroups: fixture.groups,
                savedLocations: [location],
                producerVersion: "0.1.0"
            )
        )
        let bookmarkService = SecurityScopedBookmarkService(
            resolveBookmark: { _, isStale in
                isStale = false
                return URL(fileURLWithPath: "/private/PathShelf", isDirectory: true)
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            fileExists: { _ in true }
        )
        let settingsStore = FakeSettingsStore(initial: .default)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: .default)
        )
        invocation.loadAndRegister()
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: FakeBookmarkStore(initial: []),
            favoriteGroupStore: FakeFavoriteGroupStore(initial: []),
            bookmarkService: bookmarkService
        )

        try expect(
            coordinator.preview(data)
                == .failure(.transfer(.invalidPath(location.bookmark.originalPath)))
        )
    }

    private static func testSettingsTransferRegularFileBookmark() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("not-a-folder.txt")
        try Data("fixture".utf8).write(to: fileURL)
        let fixture = try transferFixture(settings: .default)
        var location = fixture.locations[0]
        location.bookmark.originalPath = fileURL.path
        let data = try SettingsTransferCodec().encode(
            SettingsTransferCodec().makeManifest(
                settings: .default,
                favoriteGroups: fixture.groups,
                savedLocations: [location],
                producerVersion: "0.1.0"
            )
        )
        let bookmarkService = SecurityScopedBookmarkService(
            resolveBookmark: { _, isStale in
                isStale = false
                return fileURL
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            fileExists: { _ in true }
        )
        let settingsStore = FakeSettingsStore(initial: .default)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: .default)
        )
        invocation.loadAndRegister()
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: FakeBookmarkStore(initial: []),
            favoriteGroupStore: FakeFavoriteGroupStore(initial: []),
            bookmarkService: bookmarkService,
            navigationPolicy: NavigationAccessPolicy(homeRoot: directory.url)
        )

        try expect(
            coordinator.preview(data)
                == .failure(.transfer(.invalidPath(fileURL.path)))
        )
    }

    private static func testSettingsTransferCanonicalDuplicateFavorite() throws {
        let directory = try TemporaryDirectory()
        let destination = directory.url.appendingPathComponent("destination", isDirectory: true)
        let alias = directory.url.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: destination
        )
        let fixture = try transferFixture(settings: .default)
        var direct = fixture.locations[0]
        direct.bookmark.originalPath = destination.path
        var linked = direct
        linked.id = UUID(uuidString: "00000000-0000-0000-0000-000000000045")!
        linked.sortOrder = direct.sortOrder + 1
        linked.bookmark.originalPath = alias.path
        let data = try SettingsTransferCodec().encode(
            SettingsTransferCodec().makeManifest(
                settings: .default,
                favoriteGroups: fixture.groups,
                savedLocations: [direct, linked],
                producerVersion: "0.1.0"
            )
        )
        let bookmarkService = SecurityScopedBookmarkService(
            resolveBookmark: { bookmark, isStale in
                isStale = false
                return URL(fileURLWithPath: bookmark.originalPath, isDirectory: true)
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in },
            fileExists: { _ in true }
        )
        let settingsStore = FakeSettingsStore(initial: .default)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: .default)
        )
        invocation.loadAndRegister()
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: FakeBookmarkStore(initial: []),
            favoriteGroupStore: FakeFavoriteGroupStore(initial: []),
            bookmarkService: bookmarkService,
            navigationPolicy: NavigationAccessPolicy(homeRoot: directory.url)
        )
        let canonicalPath = destination.resolvingSymlinksInPath()
            .standardizedFileURL.path

        try expect(
            coordinator.preview(data)
                == .failure(.transfer(.duplicatePath(canonicalPath)))
        )
    }

    private static func testSettingsTransferImport() throws {
        let previous = AppSettings.default
        let candidate = AppSettings(
            panelPlacement: PanelPlacementPreference(mode: .activeDisplayTopCenter),
            shortcut: ShortcutBinding(keyCode: 12, modifiers: [.control]),
            launchAtLogin: false,
            showHiddenFiles: true,
            visibleDetailColumns: [.modified, .kind],
            defaultLocationPath: "/Users/example/Imported"
        )
        let fixture = try transferFixture(settings: candidate)
        let settingsStore = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let invocation = InvocationController(settingsStore: settingsStore, hotKeyController: hotKey)
        invocation.loadAndRegister()
        let bookmarks = FakeBookmarkStore(initial: [])
        let groups = FakeFavoriteGroupStore(initial: [])
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: bookmarks,
            favoriteGroupStore: groups
        )

        let result = coordinator.replace(with: fixture.data)
        guard case .success(let imported) = result else {
            throw ContractTestFailure("Expected settings transfer import to succeed: \(result)")
        }

        try expect(settingsStore.settings == candidate)
        try expect(invocation.settings == candidate)
        try expect(hotKey.activeBinding == candidate.shortcut)
        try expect(groups.groups == fixture.groups)
        try expect(bookmarks.locations.map(\.id) == fixture.locations.map(\.id))
        try expect(imported.unresolvedLocationCount == 1)
    }

    private static func testSettingsTransferPreview() throws {
        let previous = AppSettings.default
        let candidate = AppSettings(showHiddenFiles: true)
        let fixture = try transferFixture(settings: candidate)
        let settingsStore = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let invocation = InvocationController(settingsStore: settingsStore, hotKeyController: hotKey)
        invocation.loadAndRegister()
        let bookmarks = FakeBookmarkStore(initial: [])
        let groups = FakeFavoriteGroupStore(initial: [])
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: bookmarks,
            favoriteGroupStore: groups
        )

        guard case .success(let preview) = coordinator.preview(fixture.data) else {
            throw ContractTestFailure("Expected settings transfer preview to succeed")
        }

        try expect(preview.settings == candidate)
        try expect(preview.favoriteGroups == fixture.groups)
        try expect(preview.savedLocations.map(\.id) == fixture.locations.map(\.id))
        try expect(preview.unresolvedLocationCount == 1)
        try expect(bookmarks.saveCount == 0)
        try expect(groups.saveCount == 0)
        try expect(settingsStore.settings == previous)
        try expect(invocation.settings == previous)
    }

    private static func testSettingsTransferImportRollback() throws {
        let previous = AppSettings.default
        let candidate = AppSettings(
            shortcut: ShortcutBinding(keyCode: 12, modifiers: [.control]),
            showHiddenFiles: true
        )
        let fixture = try transferFixture(settings: candidate)
        let oldGroup = FavoriteGroup(name: "Existing", sortOrder: 0)
        let oldLocation = SavedLocation(
            displayName: "Existing",
            bookmark: PersistedBookmark(
                data: Data([0x10]),
                originalPath: "/Users/example/Existing",
                isSecurityScoped: false
            ),
            sortOrder: 0,
            groupID: oldGroup.id
        )
        let settingsStore = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let invocation = InvocationController(settingsStore: settingsStore, hotKeyController: hotKey)
        invocation.loadAndRegister()
        let bookmarks = FakeBookmarkStore(initial: [oldLocation], failSaveCalls: [1])
        let groups = FakeFavoriteGroupStore(initial: [oldGroup])
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: bookmarks,
            favoriteGroupStore: groups
        )

        guard case .failure = coordinator.replace(with: fixture.data) else {
            throw ContractTestFailure("Expected settings transfer persistence failure")
        }

        try expect(settingsStore.settings == previous)
        try expect(invocation.settings == previous)
        try expect(hotKey.activeBinding == previous.shortcut)
        try expect(groups.groups == [oldGroup])
        try expect(bookmarks.locations == [oldLocation])
    }

    private static func testSettingsTransferShortcutConflict() throws {
        let previous = AppSettings.default
        let candidate = AppSettings(shortcut: ShortcutBinding(keyCode: 12, modifiers: [.control]))
        let fixture = try transferFixture(settings: candidate)
        let settingsStore = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        hotKey.failBinding = candidate.shortcut
        let invocation = InvocationController(settingsStore: settingsStore, hotKeyController: hotKey)
        invocation.loadAndRegister()
        let bookmarks = FakeBookmarkStore(initial: [])
        let groups = FakeFavoriteGroupStore(initial: [])
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: bookmarks,
            favoriteGroupStore: groups
        )

        try expect(
            coordinator.replace(with: fixture.data)
                == .failure(.transaction(.hotKey(.alreadyRegistered)))
        )
        try expect(bookmarks.saveCount == 0)
        try expect(groups.saveCount == 0)
        try expect(settingsStore.settings == previous)
    }

    private static func testSettingsTransferLaunchUnavailable() throws {
        let previous = AppSettings.default
        var candidate = previous
        candidate.launchAtLogin = true
        let fixture = try transferFixture(settings: candidate)
        let settingsStore = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let launch = FakeLaunchAtLoginManager(status: .notFound)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: hotKey,
            launchAtLoginController: launch
        )
        invocation.loadAndRegister()
        let bookmarks = FakeBookmarkStore(initial: [])
        let groups = FakeFavoriteGroupStore(initial: [])
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: bookmarks,
            favoriteGroupStore: groups
        )

        try expect(
            coordinator.replace(with: fixture.data)
                == .failure(
                    .transaction(
                        .contradictoryLaunchAtLoginStatus(
                            requestedEnabled: true,
                            actual: .notFound
                        )
                    )
                )
        )
        try expect(bookmarks.saveCount == 0)
        try expect(groups.saveCount == 0)
        try expect(settingsStore.settings == previous)
    }

    private static func testSettingsTransferRollbackFailure() throws {
        let previous = AppSettings.default
        let candidate = AppSettings(shortcut: ShortcutBinding(keyCode: 12, modifiers: [.control]))
        let fixture = try transferFixture(settings: candidate)
        let oldGroup = FavoriteGroup(name: "Existing", sortOrder: 0)
        let settingsStore = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let invocation = InvocationController(settingsStore: settingsStore, hotKeyController: hotKey)
        invocation.loadAndRegister()
        let bookmarks = FakeBookmarkStore(initial: [], failSaveCalls: [1])
        let groups = FakeFavoriteGroupStore(initial: [oldGroup], failSaveCalls: [2])
        let coordinator = SettingsTransferCoordinator(
            invocationController: invocation,
            bookmarkStore: bookmarks,
            favoriteGroupStore: groups
        )

        guard case .failure(.transaction(.rollbackFailed(_, _))) = coordinator.replace(with: fixture.data) else {
            throw ContractTestFailure("Expected distinct settings transfer rollback failure")
        }
    }

    private static func testSettingsTransferRollbackRestoresDisabledLaunchRuntime() throws {
        let previous = AppSettings(launchAtLogin: true)
        let settingsStore = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        invocation.loadAndRegister()

        let result = invocation.commitImportedSettings(
            previous,
            persistAdditionalStores: { throw FakeStoreError.saveFailed },
            rollbackAdditionalStores: {}
        )

        guard case .failure(.persistence) = result else {
            throw ContractTestFailure("Expected imported settings persistence failure")
        }
        try expect(launch.enabled == false)
        try expect(launch.status == .notRegistered)
    }

    private static func testSettingsTransferRollbackRestoresEnabledLaunchRuntime() throws {
        let previous = AppSettings(launchAtLogin: false)
        let settingsStore = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .enabled)
        let invocation = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        invocation.loadAndRegister()

        let result = invocation.commitImportedSettings(
            previous,
            persistAdditionalStores: { throw FakeStoreError.saveFailed },
            rollbackAdditionalStores: {}
        )

        guard case .failure(.persistence) = result else {
            throw ContractTestFailure("Expected imported settings persistence failure")
        }
        try expect(launch.enabled)
        try expect(launch.status == .enabled)
    }

    private static func transferFixture(
        settings: AppSettings
    ) throws -> (data: Data, groups: [FavoriteGroup], locations: [SavedLocation]) {
        let group = FavoriteGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
            name: "Imported",
            sortOrder: 0
        )
        let location = SavedLocation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000060")!,
            displayName: "Imported Folder",
            bookmark: PersistedBookmark(
                data: Data([0x20]),
                originalPath: "/Users/example/Imported",
                isSecurityScoped: false
            ),
            sortOrder: 0,
            groupID: group.id
        )
        let data = try SettingsTransferCodec().encode(
            SettingsTransferCodec().makeManifest(
                settings: settings,
                favoriteGroups: [group],
                savedLocations: [location],
                producerVersion: "0.1.0"
            )
        )
        return (data, [group], [location])
    }

    private static func testBrowserDisplayPreferences() throws {
        try expect(AppSettings.default.showHiddenFiles == false)
        try expect(AppSettings.default.visibleDetailColumns == [.modified])
        try expect(AppSettings.default.defaultLocationPath == nil)

        let oldJSON = Data("""
        {
          "panelPlacement": { "mode": "cursorAdjacent" },
          "shortcut": { "keyCode": 31, "modifiers": ["control"] },
          "launchAtLogin": false
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldJSON)
        try expect(decoded.showHiddenFiles == false)
        try expect(decoded.visibleDetailColumns == [.modified])
        try expect(decoded.defaultLocationPath == nil)
    }

    private static func testMissingSettingsIsExplicit() throws {
        let directory = try TemporaryDirectory()
        let store = SettingsStore(
            storageURL: directory.url.appendingPathComponent("settings.json")
        )

        do {
            _ = try store.load()
            throw ContractTestFailure("Expected missing settings file to throw")
        } catch SettingsStoreError.missingFile {
        }
    }

    private static func testDefaultShortcutValidation() throws {
        try expect(ShortcutBinding.default.isValidForGlobalRegistration)
        try expect(
            ShortcutBinding.default.modifiers.contains(.command)
                || ShortcutBinding.default.modifiers.contains(.control)
        )
    }

    private static func testInvalidShortcutValidation() throws {
        let invalid = ShortcutBinding(keyCode: ShortcutBinding.default.keyCode, modifiers: [.option, .shift])
        try expect(invalid.isValidForGlobalRegistration == false)
    }

    private static func testCarbonHotKeyErrorMapping() throws {
        try expect(HotKeyRegistrationError(status: -9878) == .alreadyRegistered)
        try expect(HotKeyRegistrationError(status: -9868) == .internalError)
    }

    private static func testCursorAdjacentPlacement() throws {
        let calculator = PanelPlacementCalculator(
            panelSize: CGSize(width: 100, height: 80),
            screenMargin: 10
        )
        let frame = calculator.frame(
            mode: .cursorAdjacent,
            cursor: CGPoint(x: 290, y: 20),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 200)
        )

        try expect(frame.maxX <= 290)
        try expect(frame.minY >= 10)
        try expect(frame.size == CGSize(width: 100, height: 80))
    }

    private static func testTopCenterPlacement() throws {
        let calculator = PanelPlacementCalculator(
            panelSize: CGSize(width: 100, height: 80),
            screenMargin: 10
        )
        let frame = calculator.frame(
            mode: .activeDisplayTopCenter,
            cursor: CGPoint(x: 0, y: 0),
            visibleFrame: CGRect(x: 100, y: 50, width: 400, height: 300)
        )

        try expect(frame.origin == CGPoint(x: 250, y: 260))
        try expect(frame.size == CGSize(width: 100, height: 80))
    }

    private static func testHomeDirectoryProvider() throws {
        let provider = HomeDirectoryProvider()

        try expect(provider.homeDirectory == FileManager.default.homeDirectoryForCurrentUser)
        try expect(FileManager.default.fileExists(atPath: provider.homeDirectory.path))
    }

    private static func testSecurityScopedBookmarkResolution() throws {
        let directory = try TemporaryDirectory()
        let service = SecurityScopedBookmarkService()
        let bookmark = try service.makeBookmark(for: directory.url)

        try expect(bookmark.isSecurityScoped, "bookmark should be security scoped")
        try expect(bookmark.originalPath == directory.url.path, "bookmark should preserve original path")
        try expect(bookmark.data.isEmpty == false, "bookmark data should not be empty")

        let resolution = service.resolve(bookmark)

        try expect(resolution.availability == .available, "resolution availability was \(resolution.availability)")
        try expect(resolution.isStale == false, "bookmark unexpectedly stale")
        try expect(resolution.error == nil, "resolution error was \(String(describing: resolution.error))")
        try expect(
            resolution.scopedURL?.url.resolvingSymlinksInPath().path
                == directory.url.resolvingSymlinksInPath().path,
            "resolved path was \(resolution.scopedURL?.url.path ?? "nil")"
        )
        resolution.scopedURL?.close()
    }

    private static func testInvalidBookmarkResolution() throws {
        let service = SecurityScopedBookmarkService()
        let bookmark = PersistedBookmark(
            data: Data("not a bookmark".utf8),
            originalPath: "/definitely/missing",
            isSecurityScoped: true
        )

        let resolution = service.resolve(bookmark)

        try expect(resolution.scopedURL == nil)
        try expect(resolution.availability == .unavailable)
        try expect(resolution.error == .invalidBookmark(originalPath: "/definitely/missing"))
    }

    private static func testSecurityScopedStartFailureIsPermissionDenied() throws {
        let directory = try TemporaryDirectory()
        let bookmark = PersistedBookmark(
            data: Data("synthetic".utf8),
            originalPath: directory.url.path,
            isSecurityScoped: true
        )
        let service = SecurityScopedBookmarkService(
            resolveBookmark: { _, isStale in
                isStale = false
                return directory.url
            },
            startAccessing: { _ in false },
            stopAccessing: { _ in },
            fileExists: { _ in true }
        )

        let resolution = service.resolve(bookmark)

        try expect(resolution.scopedURL == nil)
        try expect(resolution.availability == .permissionDenied)
        try expect(resolution.error == .permissionDenied(originalPath: directory.url.path))
    }

    private static func testDirectoryEnumeration() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("alpha.txt")
        let nestedURL = directory.url.appendingPathComponent("Nested", isDirectory: true)
        try Data("alpha".utf8).write(to: fileURL)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let result = try runAsync {
            try await DirectoryEnumerator().enumerate(directory.url)
        }

        try expect(result.completedOnMainThread == false)
        try expect(result.items.map(\.name) == ["alpha.txt", "Nested"])
        try expect(result.items.first { $0.name == "alpha.txt" }?.kind == .file)
        try expect(result.items.first { $0.name == "alpha.txt" }?.byteSize == 5)
        try expect(result.items.first { $0.name == "Nested" }?.kind == .directory)
    }

    private static func testHiddenFileEnumeration() throws {
        let directory = try TemporaryDirectory()
        try Data("visible".utf8).write(to: directory.url.appendingPathComponent("visible.txt"))
        try Data("hidden".utf8).write(to: directory.url.appendingPathComponent(".hidden.txt"))

        let hiddenByDefault = try runAsync {
            try await DirectoryEnumerator().enumerate(directory.url)
        }
        let shownWhenEnabled = try runAsync {
            try await DirectoryEnumerator(showHiddenFiles: true).enumerate(directory.url)
        }

        try expect(hiddenByDefault.items.map(\.name) == ["visible.txt"])
        try expect(shownWhenEnabled.items.map(\.name) == [".hidden.txt", "visible.txt"])
    }

    private static func testCoordinatedRead() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("read.txt")
        try Data("coordinated".utf8).write(to: fileURL)

        let result = try runAsync {
            try await FileCoordinatorService().coordinatedRead(at: fileURL)
        }

        try expect(result.completedOnMainThread == false)
        try expect(String(data: result.data, encoding: .utf8) == "coordinated")
    }

    private static func testCoordinatedReadMissingAccessorResult() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("read.txt")
        try Data("must not fallback".utf8).write(to: fileURL)
        let service = FileCoordinatorService(readCoordinator: { _ in nil })

        do {
            _ = try runAsync {
                try await service.coordinatedRead(at: fileURL)
            }
            throw ContractTestFailure("Expected missing coordinated accessor result to throw")
        } catch FileCoordinatorServiceError.accessorDidNotProduceResult {
        }
    }

    private static func testOldSettingsJSONCompatibility() throws {
        let json = """
        {
          "panelPlacement" : {
            "mode" : "activeDisplayTopCenter"
          },
          "launchAtLogin" : true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        try expect(settings.panelPlacement.mode == .activeDisplayTopCenter)
        try expect(settings.shortcut == .default)
        try expect(settings.launchAtLogin)
    }

    private static func testSettingsPersistPlacementAndShortcut() throws {
        let directory = try TemporaryDirectory()
        let store = SettingsStore(
            storageURL: directory.url.appendingPathComponent("settings.json")
        )
        let shortcut = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let settings = AppSettings(
            panelPlacement: PanelPlacementPreference(mode: .activeDisplayTopCenter),
            shortcut: shortcut,
            launchAtLogin: false
        )

        try store.save(settings)
        let decoded = try store.load()

        try expect(decoded.panelPlacement.mode == .activeDisplayTopCenter)
        try expect(decoded.shortcut == shortcut)
    }

    private static func testInvalidHotKeyCandidateNotSaved() throws {
        let original = AppSettings.default
        let store = FakeSettingsStore(initial: original)
        let hotKey = FakeHotKeyRegistrar(activeBinding: original.shortcut)
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)
        controller.loadAndRegister()

        let invalid = ShortcutBinding(keyCode: 12, modifiers: [.option, .shift])
        let result = controller.validateAndCommitShortcut(invalid)

        switch result {
        case .failure(.hotKey(.invalidBinding)):
            break
        default:
            throw ContractTestFailure("Expected invalid hotkey failure, got \(result)")
        }
        try expect(controller.settings == original)
        try expect(try store.load() == original)
        try expect(hotKey.activeBinding == original.shortcut)
    }

    private static func testStartupShortcutFailureDoesNotRegisterDefault() throws {
        let savedShortcut = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let savedSettings = AppSettings(
            panelPlacement: AppSettings.default.panelPlacement,
            shortcut: savedShortcut,
            launchAtLogin: false
        )
        let store = FakeSettingsStore(initial: savedSettings)
        let hotKey = FakeHotKeyRegistrar(activeBinding: nil)
        hotKey.failBinding = savedShortcut
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)

        controller.loadAndRegister()

        try expect(controller.settings == savedSettings)
        try expect(hotKey.registerInitialBindings == [savedShortcut])
        try expect(hotKey.activeBinding == nil)
        try expect(controller.activeShortcut == nil)
        try expect(controller.lastError == .hotKey(.alreadyRegistered))
    }

    private static func testStartupShortcutFailurePreservesPreviousActiveBinding() throws {
        let previousActive = AppSettings.default.shortcut
        let savedShortcut = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let savedSettings = AppSettings(
            panelPlacement: AppSettings.default.panelPlacement,
            shortcut: savedShortcut,
            launchAtLogin: false
        )
        let store = FakeSettingsStore(initial: savedSettings)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previousActive)
        hotKey.failBinding = savedShortcut
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)

        controller.loadAndRegister()

        try expect(controller.settings == savedSettings)
        try expect(hotKey.registerInitialBindings == [savedShortcut])
        try expect(hotKey.activeBinding == previousActive)
        try expect(controller.activeShortcut == previousActive)
        try expect(controller.lastError == .hotKey(.alreadyRegistered))
    }

    private static func testStartupShortcutSuccessUsesSavedBinding() throws {
        let savedShortcut = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let savedSettings = AppSettings(
            panelPlacement: AppSettings.default.panelPlacement,
            shortcut: savedShortcut,
            launchAtLogin: false
        )
        let store = FakeSettingsStore(initial: savedSettings)
        let hotKey = FakeHotKeyRegistrar(activeBinding: nil)
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)

        controller.loadAndRegister()

        try expect(controller.settings == savedSettings)
        try expect(hotKey.registerInitialBindings == [savedShortcut])
        try expect(hotKey.activeBinding == savedShortcut)
        try expect(controller.activeShortcut == savedShortcut)
        try expect(controller.lastError == nil)
    }

    private static func testShortcutSaveFailureRollsBack() throws {
        let previous = AppSettings.default
        let candidate = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let store = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)
        controller.loadAndRegister()
        store.failNextSave = true

        let result = controller.validateAndCommitShortcut(candidate)

        switch result {
        case .failure(.persistenceFailed):
            break
        default:
            throw ContractTestFailure("Expected persistenceFailed, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try expect(hotKey.activeBinding == previous.shortcut)
    }

    private static func testShortcutSaveAndRollbackFailureUnregisters() throws {
        let previous = AppSettings.default
        let candidate = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let store = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)
        controller.loadAndRegister()
        store.failNextSave = true
        hotKey.failBinding = previous.shortcut

        let result = controller.validateAndCommitShortcut(candidate)

        switch result {
        case .failure(.persistenceAndRollbackFailed(_, .alreadyRegistered)):
            break
        default:
            throw ContractTestFailure("Expected persistenceAndRollbackFailed, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try expect(hotKey.activeBinding == nil)
        try expect(hotKey.unregisterCount == 1)
    }

    private static func testSuccessfulShortcutCommitPersists() throws {
        let previous = AppSettings.default
        let candidate = ShortcutBinding(keyCode: 12, modifiers: [.control])
        let store = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)
        controller.loadAndRegister()

        let result = controller.validateAndCommitShortcut(candidate)

        switch result {
        case .success:
            break
        default:
            throw ContractTestFailure("Expected shortcut commit success, got \(result)")
        }
        try expect(controller.settings.shortcut == candidate)
        try expect(try store.load().shortcut == candidate)
        try expect(hotKey.activeBinding == candidate)
    }

    private static func testPlacementSaveFailureNoMemoryDivergence() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let hotKey = FakeHotKeyRegistrar(activeBinding: previous.shortcut)
        let controller = InvocationController(settingsStore: store, hotKeyController: hotKey)
        controller.loadAndRegister()
        store.failNextSave = true

        let result = controller.updatePanelPlacement(
            PanelPlacementPreference(mode: .activeDisplayTopCenter)
        )

        switch result {
        case .failure(.persistenceFailed):
            break
        default:
            throw ContractTestFailure("Expected persistenceFailed, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
    }

    private static func testBrowserPreferencesPersist() throws {
        let store = FakeSettingsStore(initial: .default)
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: .default)
        )
        controller.loadAndRegister()

        let result = controller.updateBrowserPreferences(
            showHiddenFiles: true,
            visibleDetailColumns: [.modified, .kind, .size],
            defaultLocationPath: "/Users/example/Projects"
        )

        if case .failure(let error) = result {
            throw ContractTestFailure("Expected browser preference save success, got \(error)")
        }
        try expect(controller.settings.showHiddenFiles)
        try expect(controller.settings.visibleDetailColumns == [.modified, .kind, .size])
        try expect(controller.settings.defaultLocationPath == "/Users/example/Projects")
        try expect(store.settings == controller.settings)
    }

    private static func testLaunchAtLoginSuccessPersists() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        controller.loadAndRegister()

        let result = controller.updateLaunchAtLogin(enabled: true)

        try expect(result == .success(.enabled))
        try expect(controller.settings.launchAtLogin)
        try expect(try store.load().launchAtLogin)
        try expect(launch.enabled == true)
    }

    private static func testLaunchAtLoginRuntimeFailureDoesNotPersist() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        launch.failNextApply = true
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        controller.loadAndRegister()

        let result = controller.updateLaunchAtLogin(enabled: true)

        switch result {
        case .failure(.launchAtLogin):
            break
        default:
            throw ContractTestFailure("Expected launchAtLogin failure, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try expect(launch.enabled == false)
    }

    private static func testLaunchAtLoginSaveFailureRollsBack() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        controller.loadAndRegister()
        store.failNextSave = true

        let result = controller.updateLaunchAtLogin(enabled: true)

        switch result {
        case .failure(.launchAtLoginPersistenceFailed):
            break
        default:
            throw ContractTestFailure("Expected launchAtLoginPersistenceFailed, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try expect(launch.enabled == false)
    }

    private static func testLaunchAtLoginSaveAndRollbackFailure() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        controller.loadAndRegister()
        store.failNextSave = true
        launch.failRollback = true

        let result = controller.updateLaunchAtLogin(enabled: true)

        switch result {
        case .failure(.launchAtLoginPersistenceAndRollbackFailed):
            break
        default:
            throw ContractTestFailure("Expected launchAtLoginPersistenceAndRollbackFailed, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try expect(launch.enabled == true)
    }

    private static func testLaunchAtLoginUnchangedNoOps() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        controller.loadAndRegister()

        let result = controller.updateLaunchAtLogin(enabled: false)

        try expect(result == .success(.notRegistered))
        try expect(launch.applyCount == 0)
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try testLaunchAtLoginRuntimeDriftReconciles()
    }

    private static func testLaunchAtLoginRuntimeDriftReconciles() throws {
        var persistedEnabled = AppSettings.default
        persistedEnabled.launchAtLogin = true
        let disableStore = FakeSettingsStore(initial: persistedEnabled)
        let alreadyDisabled = FakeLaunchAtLoginManager(status: .notRegistered)
        let disableController = InvocationController(
            settingsStore: disableStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: persistedEnabled.shortcut),
            launchAtLoginController: alreadyDisabled
        )
        disableController.loadAndRegister()

        let disableResult = disableController.updateLaunchAtLogin(enabled: false)

        try expect(disableResult == .success(.notRegistered))
        try expect(alreadyDisabled.applyCount == 0)
        try expect(disableController.settings.launchAtLogin == false)
        try expect(try disableStore.load() == disableController.settings)

        let persistedDisabled = AppSettings.default
        let enableStore = FakeSettingsStore(initial: persistedDisabled)
        let alreadyEnabled = FakeLaunchAtLoginManager(status: .enabled)
        let enableController = InvocationController(
            settingsStore: enableStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: persistedDisabled.shortcut),
            launchAtLoginController: alreadyEnabled
        )
        enableController.loadAndRegister()

        let enableResult = enableController.updateLaunchAtLogin(enabled: true)

        try expect(enableResult == .success(.enabled))
        try expect(alreadyEnabled.applyCount == 0)
        try expect(enableController.settings.launchAtLogin)
        try expect(try enableStore.load() == enableController.settings)

        let failingStore = FakeSettingsStore(initial: persistedEnabled)
        let unchangedRuntime = FakeLaunchAtLoginManager(status: .notRegistered)
        let failingController = InvocationController(
            settingsStore: failingStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: persistedEnabled.shortcut),
            launchAtLoginController: unchangedRuntime
        )
        failingController.loadAndRegister()
        failingStore.failNextSave = true

        let failingResult = failingController.updateLaunchAtLogin(enabled: false)

        switch failingResult {
        case .failure(.launchAtLoginPersistenceFailed):
            break
        default:
            throw ContractTestFailure("Expected drift persistence failure, got \(failingResult)")
        }
        try expect(unchangedRuntime.applyCount == 0)
        try expect(failingController.settings == persistedEnabled)
        try expect(try failingStore.load() == persistedEnabled)

        let coherentStore = FakeSettingsStore(initial: persistedEnabled)
        coherentStore.failNextSave = true
        let driftedRuntime = FakeLaunchAtLoginManager(status: .notRegistered)
        let coherentController = InvocationController(
            settingsStore: coherentStore,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: persistedEnabled.shortcut),
            launchAtLoginController: driftedRuntime
        )
        coherentController.loadAndRegister()

        let coherentResult = coherentController.updateLaunchAtLogin(enabled: true)

        try expect(coherentResult == .success(.enabled))
        try expect(driftedRuntime.applyCount == 1)
        try expect(coherentController.settings == persistedEnabled)
        try expect(try coherentStore.load() == persistedEnabled)
        try expect(coherentStore.failNextSave)
    }

    private static func testLaunchAtLoginContradictoryStatusDoesNotPersist() throws {
        let previous = AppSettings.default
        let store = FakeSettingsStore(initial: previous)
        let launch = FakeLaunchAtLoginManager(status: .notRegistered)
        launch.nextSuccessStatus = .notFound
        let controller = InvocationController(
            settingsStore: store,
            hotKeyController: FakeHotKeyRegistrar(activeBinding: previous.shortcut),
            launchAtLoginController: launch
        )
        controller.loadAndRegister()

        let result = controller.updateLaunchAtLogin(enabled: true)

        switch result {
        case .failure(.launchAtLogin):
            break
        default:
            throw ContractTestFailure("Expected launchAtLogin contradictory failure, got \(result)")
        }
        try expect(controller.settings == previous)
        try expect(try store.load() == previous)
        try expect(launch.applyCount == 1)
    }

    private static func testShortcutKeyChoiceMapping() throws {
        try expect(ShortcutKeyChoice.choice(for: 49).displayName == "Space")
        try expect(ShortcutKeyChoice.choice(for: UInt32.max).displayName == "O")
        try expect(ShortcutKeyChoice.supported.contains { $0.displayName == "A" })
        try expect(ShortcutKeyChoice.supported.contains { $0.displayName == "9" })
    }

    private static func testSettingsStatusFormatter() throws {
        try expect(SettingsStatusFormatter.describe(.enabled) == "Enabled")
        try expect(SettingsStatusFormatter.describe(.requiresApproval) == "Requires approval in System Settings")
        try expect(SettingsStatusFormatter.describe(.notRegistered) == "Not registered")
        try expect(
            SettingsStatusFormatter.describe(.notFound)
                == "Available after PathShelf is installed in Applications."
        )
    }

    private static func testPlacementCalculationDeterministic() throws {
        let calculator = PanelPlacementCalculator(
            panelSize: CGSize(width: 120, height: 90),
            screenMargin: 8
        )
        let cursor = CGPoint(x: 220, y: 180)
        let visibleFrame = CGRect(x: 10, y: 20, width: 500, height: 400)
        let first = calculator.frame(
            mode: .cursorAdjacent,
            cursor: cursor,
            visibleFrame: visibleFrame
        )
        let second = calculator.frame(
            mode: .cursorAdjacent,
            cursor: cursor,
            visibleFrame: visibleFrame
        )

        try expect(first == second)
    }

    private static func testSettingsTransferCaseDistinctPaths() throws {
        let fixture = try transferFixture(settings: .default)
        var upper = fixture.locations[0]
        upper.bookmark.originalPath = "/Volumes/CaseSensitive/Project"
        var lower = upper
        lower.id = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        lower.sortOrder = upper.sortOrder + 1
        lower.bookmark.originalPath = "/Volumes/CaseSensitive/project"

        let manifest = try SettingsTransferCodec().makeManifest(
            settings: .default,
            favoriteGroups: fixture.groups,
            savedLocations: [upper, lower],
            producerVersion: "0.1.0"
        )

        try expect(manifest.savedLocations.count == 2)
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

        Task {
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

        semaphore.wait()
        return try box.withValue { value in
            guard let value else {
                throw ContractTestFailure("Async operation did not produce a result")
            }
            return try value.get()
        }
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

private final class FakeSettingsStore: SettingsPersisting, @unchecked Sendable {
    var settings: AppSettings
    var failNextSave = false

    init(initial: AppSettings) {
        self.settings = initial
    }

    func load() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        if failNextSave {
            failNextSave = false
            throw FakeStoreError.saveFailed
        }
        self.settings = settings
    }
}

private final class FakeBookmarkStore: BookmarkStore, @unchecked Sendable {
    var locations: [SavedLocation]
    var failSaveCalls: Set<Int>
    var saveCount = 0

    init(initial: [SavedLocation], failSaveCalls: Set<Int> = []) {
        self.locations = initial
        self.failSaveCalls = failSaveCalls
    }

    func loadSavedLocations() throws -> [SavedLocation] {
        locations
    }

    func saveSavedLocations(_ locations: [SavedLocation]) throws {
        saveCount += 1
        if failSaveCalls.contains(saveCount) {
            throw FakeStoreError.saveFailed
        }
        self.locations = locations
    }
}

private final class FakeFavoriteGroupStore: FavoriteGroupStore, @unchecked Sendable {
    var groups: [FavoriteGroup]
    var failSaveCalls: Set<Int>
    var saveCount = 0

    init(initial: [FavoriteGroup], failSaveCalls: Set<Int> = []) {
        self.groups = initial
        self.failSaveCalls = failSaveCalls
    }

    func loadFavoriteGroups() throws -> [FavoriteGroup] {
        groups
    }

    func saveFavoriteGroups(_ groups: [FavoriteGroup]) throws {
        saveCount += 1
        if failSaveCalls.contains(saveCount) {
            throw FakeStoreError.saveFailed
        }
        self.groups = groups
    }
}

private enum FakeStoreError: Error, CustomStringConvertible {
    case saveFailed

    var description: String {
        "saveFailed"
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistering, @unchecked Sendable {
    var activeBinding: ShortcutBinding?
    var failBinding: ShortcutBinding?
    var unregisterCount = 0
    var registerInitialBindings: [ShortcutBinding] = []

    init(activeBinding: ShortcutBinding?) {
        self.activeBinding = activeBinding
    }

    func registerInitial(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError> {
        registerInitialBindings.append(binding)
        return validateAndCommit(binding)
    }

    func validateAndCommit(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError> {
        guard binding.isValidForGlobalRegistration else {
            return .failure(.invalidBinding)
        }
        if binding == failBinding {
            return .failure(.alreadyRegistered)
        }
        activeBinding = binding
        return .success(())
    }

    func unregister() {
        activeBinding = nil
        unregisterCount += 1
    }
}

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    var status: LaunchAtLoginStatus
    var enabled: Bool
    var failNextApply = false
    var failRollback = false
    var applyCount = 0
    var nextSuccessStatus: LaunchAtLoginStatus?

    init(status: LaunchAtLoginStatus) {
        self.status = status
        self.enabled = status == .enabled
    }

    func apply(enabled: Bool) -> Result<LaunchAtLoginStatus, LaunchAtLoginError> {
        applyCount += 1
        if failNextApply {
            failNextApply = false
            return .failure(.runtimeFailed("apply failed"))
        }
        if failRollback && enabled == false {
            return .failure(.runtimeFailed("rollback failed"))
        }
        self.enabled = enabled
        self.status = nextSuccessStatus ?? (enabled ? .enabled : .notRegistered)
        nextSuccessStatus = nil
        return .success(status)
    }
}
