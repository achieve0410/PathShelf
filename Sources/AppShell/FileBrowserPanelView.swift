import AppKit
import FileAccess
import FileOperations
import PanelFeature
import PreviewFeature
import SettingsFeature

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
    let statusLabel = NSTextField(labelWithString: "")
    let sidebarTitleLabel = NSTextField(labelWithString: "FAVORITES")
    let browserStateView = BrowserStateView()
    let sidebarTable = KeyHandlingTableView()
    let fileTable = KeyHandlingTableView()
    weak var bottomBarView: NSView?
    weak var splitView: NSSplitView?
    weak var sidebarScrollView: NSScrollView?
    weak var fileScrollView: NSScrollView?
    let sidebarDataSource: SavedLocationTableDataSource
    let fileDataSource: FileTableDataSource
    private(set) var toolbarControlCount = 0
    private var loadTask: Task<Void, Never>?
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
                && contextFavoriteAdded
                && spaceQuickLookReady,
            "headerSortChanged=\(headerSortChanged) contextSelected=\(contextSelected) "
                + "contextCleared=\(contextCleared) quickLookMenuRemoved=\(quickLookMenuRemoved) "
                + "fileMenuTargetsReady=\(fileMenuTargetsReady) openWithTargetsReady=\(openWithTargetsReady) "
                + "favoriteRevealReady=\(favoriteRevealReady) "
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
