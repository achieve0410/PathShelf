import AppKit
import FileAccess
import FileOperations
import PanelFeature
import PreviewFeature
import SettingsFeature

struct KeyboardReauthorizationProbeResult {
    var targetingReady: Bool
    var preservesBrowserState: Bool
}

struct PanelFilterProbeResult {
    let searchControlReady: Bool
    let accessibilityReady: Bool
    let keyboardFocusReady: Bool
    let escapeClearReady: Bool
    let loadingStateReady: Bool
    let narrowsItems: Bool
    let showsNoResults: Bool
    let clearsFilter: Bool
    let captureReady: Bool

    static let unavailable = PanelFilterProbeResult(
        searchControlReady: false,
        accessibilityReady: false,
        keyboardFocusReady: false,
        escapeClearReady: false,
        loadingStateReady: false,
        narrowsItems: false,
        showsNoResults: false,
        clearsFilter: false,
        captureReady: false
    )
}

struct PathBarBoundaryProbeResult {
    let preserved: Bool
    let captureReady: Bool

    static let unavailable = PathBarBoundaryProbeResult(
        preserved: false,
        captureReady: false
    )
}

struct FavoriteUsabilityProbeResult {
    let addControlReady: Bool
    let returnActivationReady: Bool
    let accessibilityReady: Bool

    static let unavailable = FavoriteUsabilityProbeResult(
        addControlReady: false,
        returnActivationReady: false,
        accessibilityReady: false
    )
}

@MainActor
final class PanelContentView: NSView, NSMenuItemValidation {
    static let favoriteGroupIconChoices: [(title: String, symbol: String)] = [
        ("Folder", "folder.fill"),
        ("Work", "briefcase.fill"),
        ("Personal", "person.fill"),
        ("Project", "hammer.fill"),
        ("Archive", "archivebox.fill"),
        ("Star", "star.fill")
    ]

    let focusView: PanelFocusView

    let model: FileBrowserModel
    let workspaceService: WorkspaceActionService
    let thumbnailService: ThumbnailService
    let settingsStore: SettingsStore
    let quickLookCoordinator: QuickLookPanelCoordinator
    let pathControl = PathBarControl()
    let searchField = FilterSearchField()
    let statusLabel = NSTextField(labelWithString: "")
    let sidebarTitleLabel = NSTextField(labelWithString: "FAVORITES")
    let addFavoriteButton = NSButton()
    let browserStateView = BrowserStateView()
    let sidebarTable = KeyHandlingTableView()
    let fileTable = KeyHandlingTableView()
    weak var searchBarView: NSView?
    weak var bottomBarView: NSView?
    weak var splitView: NSSplitView?
    weak var sidebarScrollView: NSScrollView?
    weak var fileScrollView: NSScrollView?
    let sidebarDataSource: SavedLocationTableDataSource
    let fileDataSource: FileTableDataSource
    private(set) var toolbarControlCount = 0
    private(set) var loadingPresentationCount = 0
    var onLoadingPresented: (() -> Void)?
    private var loadTask: Task<Void, Never>?
    var favoriteActivationTask: Task<Void, Never>?
    var thumbnailTasks: [URL: Task<Void, Never>] = [:]
    var isTornDown = false
    var contextItemURL: URL?
    var contextSidebarItem: FavoriteSidebarItem?
    let onEscape: () -> Void

    init(
        model: FileBrowserModel,
        workspaceService: WorkspaceActionService,
        thumbnailService: ThumbnailService,
        settingsStore: SettingsStore,
        quickLookCoordinator: QuickLookPanelCoordinator,
        onEscape: @escaping () -> Void
    ) {
        self.model = model
        self.workspaceService = workspaceService
        self.thumbnailService = thumbnailService
        self.settingsStore = settingsStore
        self.quickLookCoordinator = quickLookCoordinator
        self.onEscape = onEscape
        self.focusView = PanelFocusView(onEscape: onEscape)
        self.sidebarDataSource = SavedLocationTableDataSource(model: model)
        self.fileDataSource = FileTableDataSource(model: model)
        super.init(frame: .zero)
        focusView.contentView = self
        setup()
        model.onLoadingStateChange = { [weak self] isLoading in
            guard let self else {
                return
            }
            refreshTables()
            if isLoading && browserStateView.currentTitle == "Loading…" {
                loadingPresentationCount += 1
                onLoadingPresented?()
            }
        }
    }

    override init(frame frameRect: NSRect) {
        let previewController = QuickLookPreviewController()
        let bookmarkService = SecurityScopedBookmarkService()
        let bookmarkStore = JSONBookmarkStore(storageURL: ApplicationPaths.bookmarksURL())
        let favoriteGroupStore = JSONFavoriteGroupStore(
            storageURL: ApplicationPaths.favoriteGroupsURL()
        )
        let lifecycleDiagnostics = LifecycleDiagnostics()
        let model = FileBrowserModel(
            environment: FileBrowserEnvironment(
                loadSavedLocations: { try bookmarkStore.loadSavedLocations() },
                saveSavedLocations: { try bookmarkStore.saveSavedLocations($0) },
                loadFavoriteGroups: { try favoriteGroupStore.loadFavoriteGroups() },
                saveFavoriteGroups: { try favoriteGroupStore.saveFavoriteGroups($0) },
                makeBookmark: { try bookmarkService.makeBookmark(for: $0) },
                resolveBookmark: { bookmarkService.resolve($0) },
                previewController: previewController,
                visibleDirectoryMonitor: VisibleDirectoryMonitor(diagnostics: lifecycleDiagnostics),
                volumeEventObserver: VolumeEventObserver(diagnostics: lifecycleDiagnostics),
                lifecycleDiagnostics: lifecycleDiagnostics
            )
        )
        self.model = model
        self.workspaceService = WorkspaceActionService()
        self.thumbnailService = ThumbnailService()
        self.settingsStore = SettingsStore(storageURL: ApplicationPaths.settingsURL())
        self.quickLookCoordinator = QuickLookPanelCoordinator(contractController: previewController)
        self.onEscape = {}
        self.focusView = PanelFocusView(onEscape: {})
        self.sidebarDataSource = SavedLocationTableDataSource(model: model)
        self.fileDataSource = FileTableDataSource(model: model)
        super.init(frame: frameRect)
        focusView.contentView = self
        setup()
    }

    var snapshot: BrowserSnapshot {
        model.snapshot
    }

    func start() {
        isTornDown = false
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            await model.loadInitialState()
            model.startLifecycleMonitoring()
            refreshTables()
            startThumbnailRequests()
        }
    }

    func startAndWaitForInteractive() async -> BrowserSnapshot {
        isTornDown = false
        loadTask?.cancel()
        loadTask = nil
        await model.loadInitialState()
        model.startLifecycleMonitoring()
        refreshInteractiveState()
        return model.snapshot
    }

    func awaitInitialLoad() async {
        await loadTask?.value
    }

    func runKeyboardReauthorizationStateProbe(
        in directoryURL: URL
    ) async -> KeyboardReauthorizationProbeResult {
        let originalDirectory = model.currentDirectoryURL
        await model.navigateToPathBarLocation(directoryURL)
        let directoryBefore = model.currentDirectoryURL.standardizedFileURL
        guard directoryBefore == directoryURL.standardizedFileURL else {
            return KeyboardReauthorizationProbeResult(
                targetingReady: false,
                preservesBrowserState: false
            )
        }
        let probeID = UUID()
        let targetingReady = Self.reauthorizationTargetID(
            selectedRow: -1,
            visibleItems: [],
            savedLocations: [
                SavedLocation(
                    id: probeID,
                    displayName: "Needs Access",
                    bookmark: PersistedBookmark(
                        data: Data([0x00]),
                        originalPath: "/Users/old-user/Missing",
                        isSecurityScoped: true
                    ),
                    sortOrder: 0,
                    availability: .permissionDenied
                )
            ]
        ) == probeID
        await awaitInitialLoad()
        let preserved = model.currentDirectoryURL.standardizedFileURL == directoryBefore
        await model.navigateToPathBarLocation(originalDirectory)
        return KeyboardReauthorizationProbeResult(
            targetingReady: targetingReady,
            preservesBrowserState: preserved
                && model.currentDirectoryURL.standardizedFileURL
                    == originalDirectory.standardizedFileURL
        )
    }

    func resumeCachedInteractive() -> BrowserSnapshot {
        isTornDown = false
        loadTask?.cancel()
        loadTask = nil
        model.startLifecycleMonitoring()
        refreshInteractiveState()
        return model.snapshot
    }

    private func refreshInteractiveState() {
        if model.selectedItem == nil, model.items.isEmpty == false {
            model.select(index: 0)
        }
        refreshTables()
        if let selectedIndex = model.selectedIndex {
            fileTable.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            fileTable.scrollRowToVisible(selectedIndex)
        }
        startThumbnailRequests()
    }

    func prepareForHide() {
        isTornDown = true
        loadTask?.cancel()
        loadTask = nil
        favoriteActivationTask?.cancel()
        favoriteActivationTask = nil
        cancelThumbnailRequests()
        quickLookCoordinator.close()
        model.teardown()
        model.setActiveThumbnailCount(0)
        refreshTables()
    }

    func runSmokeActions(fixtureURL: URL) async -> BrowserSnapshot {
        await model.loadInitialState()
        try? model.addSavedLocation(url: fixtureURL, displayName: "Fixture")
        if let id = model.savedLocations.first?.id {
            try? model.renameSavedLocation(id: id, to: "Fixture Renamed")
            try? model.moveSavedLocation(id: id, direction: 1)
            try? await model.navigateToSavedLocation(id: id)
        }
        _ = await model.createFolder(named: "Existing")
        if let first = model.items.firstIndex(where: { $0.name == "alpha.txt" }) {
            model.select(index: first)
        }
        model.presentQuickLookForSelection()
        if let item = model.selectedItem {
            _ = workspaceService.compatibleApplications(for: item.url)
        }
        quickLookCoordinator.present(model.selectedItem?.url)
        prepareForHide()
        return model.snapshot
    }

    func runPathBarBoundaryProbe(fixtureURL: URL) async -> Bool {
        await model.loadInitialState()
        if model.savedLocations.contains(where: {
            $0.bookmark.originalPath == fixtureURL.path
        }) == false {
            try? model.addSavedLocation(url: fixtureURL, displayName: "Boundary Root")
        }
        guard let id = model.savedLocations.first(where: {
            $0.bookmark.originalPath == fixtureURL.path
        })?.id else {
            return false
        }

        do {
            try await model.navigateToSavedLocation(id: id)
        } catch {
            return false
        }
        let childURL = fixtureURL
            .appendingPathComponent("Existing", isDirectory: true)
            .appendingPathComponent("BoundaryChild", isDirectory: true)
        await model.navigateToPathBarLocation(childURL)
        model.setFilterQuery("inside")
        refreshTablesAndThumbnails()

        await model.navigateToPathBarLocation(fixtureURL.deletingLastPathComponent())
        refreshTablesAndThumbnails()

        return model.currentDirectoryURL == childURL.standardizedFileURL
            && model.items.map(\.name) == ["inside.txt"]
            && model.filterQuery == "inside"
            && pathControl.url == childURL.standardizedFileURL
            && fileTable.numberOfRows == 1
    }

    func runFavoriteUsabilityProbe(
        fixtureURL: URL
    ) async -> FavoriteUsabilityProbeResult {
        await model.loadInitialState()
        if model.savedLocations.contains(where: {
            $0.bookmark.originalPath == fixtureURL.path
        }) == false {
            try? model.addSavedLocation(url: fixtureURL, displayName: "Fixture")
        }
        sidebarTable.reloadData()

        let addButton = descendantButton(
            in: self,
            accessibilityIdentifier: "pathshelf.favorite.add"
        )
        let addControlReady = addButton?.title == "Add Favorite…"
            && addButton?.action == #selector(addSavedLocation(_:))
            && addButton?.target === self
            && addButton?.accessibilityLabel() == "Add Favorite"

        let visibleItems = sidebarDataSource.visibleItems
        let groupRow = visibleItems.firstIndex {
            if case .group = $0 {
                return true
            }
            return false
        }
        let locationRow = visibleItems.firstIndex {
            if case .location = $0 {
                return true
            }
            return false
        }
        let groupCell = groupRow.flatMap {
            sidebarTable.view(atColumn: 0, row: $0, makeIfNecessary: true)
        }
        let locationCell = locationRow.flatMap {
            sidebarTable.view(atColumn: 0, row: $0, makeIfNecessary: true)
        }
        let disclosureButton = groupCell.flatMap {
            firstButton(in: $0)
        }
        let accessibilityReady = disclosureButton?.accessibilityLabel()
            == "Default Group"
            && disclosureButton?.accessibilityValue() as? String == "expanded"
            && locationCell?.accessibilityLabel() == "Favorite Fixture, available"

        var returnActivationReady = false
        if let locationRow {
            sidebarTable.selectRowIndexes(
                IndexSet(integer: locationRow),
                byExtendingSelection: false
            )
            favoriteActivationTask = nil
            let returnEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
            if let returnEvent {
                sidebarTable.keyDown(with: returnEvent)
            }
            if let favoriteActivationTask {
                await favoriteActivationTask.value
                returnActivationReady = model.currentDirectoryURL
                    == fixtureURL.standardizedFileURL
                    && model.items.map(\.name).contains("alpha.txt")
            }
        }

        return FavoriteUsabilityProbeResult(
            addControlReady: addControlReady,
            returnActivationReady: returnActivationReady,
            accessibilityReady: accessibilityReady
        )
    }

    private func descendantButton(
        in view: NSView,
        accessibilityIdentifier: String
    ) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityIdentifier() == accessibilityIdentifier {
            return button
        }
        for child in view.subviews {
            if let button = descendantButton(
                in: child,
                accessibilityIdentifier: accessibilityIdentifier
            ) {
                return button
            }
        }
        return nil
    }

    private func firstButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton {
            return button
        }
        for child in view.subviews {
            if let button = firstButton(in: child) {
                return button
            }
        }
        return nil
    }

    func runColdInteractiveProbe() async -> BrowserSnapshot {
        await model.loadInitialState()
        refreshTables()
        return model.snapshot
    }

    func runInteractionProbe() async -> (passed: Bool, diagnostics: String) {
        guard model.items.isEmpty == false else {
            return (false, "itemsEmpty=true")
        }
        model.setSortOrder(.nameAscending)
        fileDataSource.onSortColumn?("name")
        let headerSortChanged = model.sortOrder == .nameDescending
        fileDataSource.onSortColumn?("name")

        model.select(index: nil)
        fileTable.onContextRow?(0)
        let contextSelected = model.selectedIndex == 0
        fileTable.onContextRow?(nil)
        let contextCleared = model.selectedIndex == nil

        let quickLookMenuRemoved = fileTable.menu?.items.contains {
            $0.title.localizedCaseInsensitiveContains("Quick Look")
        } == false
        let fileMenuTargetsReady = fileTable.menu?.items
            .filter { $0.isSeparatorItem == false && $0.title != "Move to Trash" }
            .allSatisfy { item in
                guard let action = item.action, let target = item.target else {
                    return false
                }
                return target.responds(to: action)
            } == true
        let openWithTargetsReady = fileTable.menu?.items
            .first(where: { $0.title == "Open With…" })?
            .submenu?.items.allSatisfy { item in
                guard let action = item.action, let target = item.target else {
                    return false
                }
                return item.isEnabled && target.responds(to: action)
            } == true
        let favoriteRevealItem = model.savedLocations.first.map {
            makeFavoriteContextMenu(for: .location($0))
        }?.items.first(where: { $0.title == "Reveal in Finder" })
        let favoriteRevealReady = favoriteRevealItem?.action == #selector(revealSavedLocation(_:))
            && favoriteRevealItem?.target?.responds(to: #selector(revealSavedLocation(_:))) == true
        let favoriteReauthorizationItem = model.savedLocations.first.map {
            makeFavoriteContextMenu(for: .location($0))
        }?.items.first(where: { $0.title == "Choose New Folder…" })
        let favoriteReauthorizationReady = favoriteReauthorizationItem?.identifier?.rawValue
            == "PathShelf.Favorites.ChooseNewFolder"
            && favoriteReauthorizationItem?.action == #selector(reauthorizeSavedLocation(_:))
            && favoriteReauthorizationItem?.target?.responds(
                to: #selector(reauthorizeSavedLocation(_:))
            ) == true

        var contextFavoriteAdded = false
        if let directoryIndex = model.items.firstIndex(where: { $0.kind == .directory }),
           let addFavoriteItem = fileTable.menu?.items.first(where: { $0.title == "Add to Favorites" }) {
            let directoryURL = model.items[directoryIndex].url
            fileTable.onContextRow?(directoryIndex)
            model.select(index: nil)
            let delivered = NSApp.sendAction(
                addFavoriteItem.action!,
                to: addFavoriteItem.target,
                from: addFavoriteItem
            )
            if let added = model.savedLocations.first(where: { $0.bookmark.originalPath == directoryURL.path }) {
                contextFavoriteAdded = delivered
                try? model.removeSavedLocation(id: added.id)
            }
        }

        var spaceQuickLookReady = false
        var quickLookDiagnostics = "htmlMissing=true"
        if let fileIndex = model.items.firstIndex(where: {
            $0.url.pathExtension.localizedCaseInsensitiveCompare("html") == .orderedSame
        }) {
            model.select(index: fileIndex)
            fileTable.onSpace?()
            try? await Task.sleep(for: .milliseconds(200))
            spaceQuickLookReady = quickLookCoordinator.isVisible
                && quickLookCoordinator.hasPreviewItem
                && quickLookCoordinator.previewedURL?.pathExtension == "html"
            quickLookDiagnostics = quickLookCoordinator.diagnostics
            quickLookCoordinator.close()
        }
        return (
            headerSortChanged
                && contextSelected
                && contextCleared
                && quickLookMenuRemoved
                && fileMenuTargetsReady
                && openWithTargetsReady
                && favoriteRevealReady
                && favoriteReauthorizationReady
                && contextFavoriteAdded
                && spaceQuickLookReady,
            "headerSortChanged=\(headerSortChanged) contextSelected=\(contextSelected) "
                + "contextCleared=\(contextCleared) quickLookMenuRemoved=\(quickLookMenuRemoved) "
                + "fileMenuTargetsReady=\(fileMenuTargetsReady) openWithTargetsReady=\(openWithTargetsReady) "
                + "favoriteRevealReady=\(favoriteRevealReady) "
                + "favoriteReauthorizationReady=\(favoriteReauthorizationReady) "
                + "contextFavoriteAdded=\(contextFavoriteAdded) spaceQuickLookReady=\(spaceQuickLookReady) "
                + "quickLook=\(quickLookDiagnostics)"
        )
    }

    func refreshSavedLocations() {
        refreshTables()
    }

    var areInteractionsReady: Bool {
        let openWithSubmenu = fileTable.menu?.items.first(where: { $0.title == "Open With…" })?.submenu
        let firstSidebarCell = sidebarTable.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let disclosureReady = firstSidebarCell?.subviews.contains {
            ($0 as? NSButton)?.bezelStyle == .disclosure
        } == true
        return sidebarTitleLabel.stringValue == "FAVORITES"
            && disclosureReady
            && sidebarTable.tableColumns.first?.title == "Favorites"
            && sidebarTable.headerView == nil
            && sidebarDataSource.onDrop != nil
            && fileTable.headerView != nil
            && fileTable.tableColumns.first?.title == "Name"
            && sidebarTable.contextMenuProvider != nil
            && fileTable.menu != nil
            && fileTable.menu?.items.contains(where: { $0.title == "New Folder…" }) == true
            && openWithSubmenu?.items.contains(where: { $0.title == "Finder" }) == true
            && pathControl.url != nil
            && pathControl.action == #selector(openPathComponent(_:))
            && pathControl.target === self
            && fileDataSource.onSortColumn != nil
            && fileTable.onContextRow != nil
            && fileTable.doubleAction == #selector(openClickedFile(_:))
    }

    var thumbnailRenderingPolicyReady: Bool {
        fileDataSource.renderingPolicyReady
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
