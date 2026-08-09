import AppKit
import Carbon.HIToolbox
import Darwin
import FileAccess
import FileOperations
import PanelFeature
import PreviewFeature
import SettingsFeature

private let appProcessProbeStart = Date()

@main
@MainActor
final class PathShelfApp: NSObject, NSApplicationDelegate {
    private let settingsStore: SettingsStore
    private var terminationSignalHandler: TerminationSignalHandler?
    private let hotKeyController = HotKeyRegistrationController()
    private var invocationController: InvocationController?
    private var hotKeyDispatcher: HotKeyEventDispatcher?
    private var panelController: FloatingPanelController?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?

    override init() {
        self.settingsStore = SettingsStore(
            storageURL: ApplicationPaths.settingsURL()
        )
        super.init()
    }

    static func main() {
        _ = appProcessProbeStart
        if ProcessInfo.processInfo.environment["PATHSHELF_PERF_LINKER_PREFLIGHT"] == "1" {
            return
        }
        let app = NSApplication.shared
        let delegate = PathShelfApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let invocationController = InvocationController(
            settingsStore: settingsStore,
            hotKeyController: hotKeyController,
            launchAtLoginController: LiveLaunchAtLoginManager()
        )
        invocationController.loadAndRegister()
        self.invocationController = invocationController
        panelController = makePanelController()
        statusItemController = StatusItemController(togglePanel: { [weak self] in
            self?.togglePanelFromFallback()
        }, openSettings: { [weak self] in
            self?.openSettings()
        })
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenuFactory.makeMainMenu(commandTarget: self)
        installHotKeyDispatcher()
        terminationSignalHandler = TerminationSignalHandler.install {
            NSApp.terminate(nil)
        }

        if ProcessInfo.processInfo.environment["PATHSHELF_SMOKE"] == "1" {
            openSettings()
            DispatchQueue.main.async { [weak self] in
                Task {
                    await self?.runSmokeProbe()
                }
            }
        } else if ProcessInfo.processInfo.environment["PATHSHELF_PERF"] == "1" {
            DispatchQueue.main.async { [weak self] in
                Task {
                    await self?.runPerformanceProbe()
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false {
            showPanel()
        }
        return true
    }

    @objc func togglePanelFromMenu(_ sender: Any?) {
        togglePanelFromFallback()
    }

    @objc func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    @objc func closeActiveWindowFromMenu(_ sender: Any?) {
        if settingsWindowController?.window?.isKeyWindow == true {
            settingsWindowController?.close()
        } else if panelController?.isPanelVisible == true {
            panelController?.hide()
        } else if settingsWindowController?.window?.isVisible == true {
            settingsWindowController?.close()
        }
    }

    private func openSettings() {
        guard let invocationController else {
            return
        }
        let controller = settingsWindowController ?? SettingsWindowController(
            invocationController: invocationController,
            onClose: { [weak self] in
                self?.synchronizeActivationPolicy()
            },
            onApply: { [weak self] in
                self?.panelController?.hide()
                self?.panelController = self?.makePanelController()
            },
            onGrantFolderAccess: { [weak self] url in
                guard let panelController = self?.panelController else {
                    throw FolderAccessGrantError.panelUnavailable
                }
                try panelController.grantFolderAccess(to: url)
            }
        )
        settingsWindowController = controller
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private func togglePanelFromFallback() {
        if panelController?.isPanelVisible == true {
            panelController?.hide()
            return
        }
        showPanel()
    }

    private func showPanel() {
        let placement = invocationController?.settings.panelPlacement.mode ?? .cursorAdjacent
        panelController?.show(
            mode: placement,
            cursor: NSEvent.mouseLocation,
            screens: NSScreen.screens
        )
    }

    private func panelVisibilityChanged(_ isVisible: Bool) {
        if isVisible {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        } else {
            synchronizeActivationPolicy()
        }
    }

    private func synchronizeActivationPolicy() {
        let hasVisibleAppWindow = panelController?.isPanelVisible == true
            || settingsWindowController?.window?.isVisible == true
        NSApp.setActivationPolicy(hasVisibleAppWindow ? .regular : .accessory)
    }

    private func installHotKeyDispatcher() {
        do {
            let dispatcher = HotKeyEventDispatcher { [weak self] in
                self?.togglePanelFromFallback()
            }
            try dispatcher.install()
            hotKeyDispatcher = dispatcher
        } catch {
            NSLog("PathShelf hotkey event handler could not be installed: \(error)")
        }
    }

    private func makePanelController() -> FloatingPanelController {
        let isProbe = ProcessInfo.processInfo.environment["PATHSHELF_SMOKE"] == "1"
            || ProcessInfo.processInfo.environment["PATHSHELF_PERF"] == "1"
        let homeURL = isProbe
            ? ApplicationPaths.smokeFixtureURL()
            : HomeDirectoryProvider().homeDirectory
        let settingsStore = self.settingsStore
        let bookmarkStore = JSONBookmarkStore(storageURL: ApplicationPaths.bookmarksURL())
        let favoriteGroupStore = JSONFavoriteGroupStore(
            storageURL: ApplicationPaths.favoriteGroupsURL()
        )
        let bookmarkService = SecurityScopedBookmarkService()
        let previewController = QuickLookPreviewController()
        let lifecycleDiagnostics = LifecycleDiagnostics()
        let model = FileBrowserModel(
            environment: FileBrowserEnvironment(
                homeDirectory: { homeURL },
                initialDirectory: {
                    var isDirectory: ObjCBool = false
                    guard isProbe == false,
                          let path = (try? settingsStore.load())?.defaultLocationPath,
                          FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        return homeURL
                    }
                    return URL(fileURLWithPath: path, isDirectory: true)
                },
                enumerate: { url in
                    let showHiddenFiles = (try? settingsStore.load())?.showHiddenFiles ?? false
                    return try await DirectoryEnumerator(
                        showHiddenFiles: showHiddenFiles
                    ).enumerate(url)
                },
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
        return FloatingPanelController(
            model: model,
            workspaceService: WorkspaceActionService(),
            thumbnailService: ThumbnailService(),
            settingsStore: settingsStore,
            quickLookCoordinator: QuickLookPanelCoordinator(contractController: previewController),
            onVisibilityChanged: { [weak self] isVisible in
                self?.panelVisibilityChanged(isVisible)
            }
        )
    }

    private func runSmokeProbe() async {
        let hotKeyRegistered = invocationController?.activeShortcut != nil
        let fallbackReady = NSApp.mainMenu != nil && statusItemController?.isReady == true
        let statusIconReady = statusItemController?.hasVisibleIcon == true
        let welcomeVisible = settingsWindowController?.window?.isVisible == true
        let browserPreferencesReady = settingsWindowController?.browserPreferencesReady == true
        let loadedPlacement = invocationController?.settings.panelPlacement.mode ?? .cursorAdjacent
        let loadedShortcut = invocationController?.settings.shortcut ?? .default

        smokePrint("SMOKE hotkeyRegistered=\(hotKeyRegistered)")
        smokePrint("SMOKE hotkeyError=\(invocationController?.lastError?.description ?? "none")")
        smokePrint("SMOKE fallbackReady=\(fallbackReady)")
        smokePrint("SMOKE statusIconReady=\(statusIconReady)")
        smokePrint("SMOKE welcomeVisible=\(welcomeVisible)")
        smokePrint("SMOKE browserPreferencesReady=\(browserPreferencesReady)")
        smokePrint("SMOKE loadedPlacement=\(loadedPlacement.rawValue)")
        smokePrint("SMOKE loadedShortcutValid=\(loadedShortcut.isValidForGlobalRegistration)")
        settingsWindowController?.close()
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        let reopenPanelVisible = panelController?.isPanelVisible == true
        smokePrint("SMOKE reopenPanelVisible=\(reopenPanelVisible)")
        panelController?.hide()
        let fixtureURL = ApplicationPaths.smokeFixtureURL()
        do {
            try prepareSmokeFixture(at: fixtureURL)
        } catch {
            smokePrint("SMOKE fixturePrepared=false")
            smokePrint("SMOKE fixtureError=\(String(describing: error))")
        }

        panelController?.show(
            mode: loadedPlacement,
            cursor: NSEvent.mouseLocation,
            screens: NSScreen.screens
        )
        panelController?.hide()
        let warmStart = DispatchTime.now()
        panelController?.show(
            mode: loadedPlacement,
            cursor: NSEvent.mouseLocation,
            screens: NSScreen.screens
        )
        let warmLatencyMs = Double(DispatchTime.now().uptimeNanoseconds - warmStart.uptimeNanoseconds) / 1_000_000.0
        let shown = panelController?.isPanelVisible == true
        let focused = panelController?.hasKeyboardFocus == true
        try? await Task.sleep(for: .milliseconds(100))
        let appNameVisible = NSApp.activationPolicy() == .regular
            && NSApp.isActive
            && panelController?.isKeyWindow == true
            && NSApp.mainMenu?.items.first?.title == "PathShelf"
        let placementCount = panelController?.placementCalculationCount ?? 0

        let coldStart = DispatchTime.now()
        _ = await panelController?.runColdInteractiveProbe()
        let coldLatencyMs = Double(DispatchTime.now().uptimeNanoseconds - coldStart.uptimeNanoseconds) / 1_000_000.0
        let browserSnapshot = await panelController?.runSmokeBrowserProbe(fixtureURL: fixtureURL) ?? BrowserSnapshot(
            currentDirectoryURL: URL(fileURLWithPath: "/"),
            itemNames: [],
            selectedItemName: nil,
            savedLocationNames: [],
            availability: .unavailable(.unavailable, "/"),
            lastOperationStatus: nil,
            lastErrorMessage: "Smoke browser probe did not run",
            isLoading: false,
            generation: 0,
            teardownCount: 0
        )
        let interactionProbe = await panelController?.runInteractionProbe()
        panelController?.hide()
        let hidden = panelController?.isPanelVisible == false

        smokePrint("SMOKE panelShown=\(shown)")
        smokePrint("SMOKE panelFocused=\(focused)")
        smokePrint("SMOKE appNameVisible=\(appNameVisible)")
        smokePrint("SMOKE layoutReady=\(panelController?.isLayoutReady == true)")
        smokePrint("SMOKE interactionsReady=\(panelController?.areInteractionsReady == true)")
        smokePrint("SMOKE thumbnailRenderingPolicyReady=\(panelController?.thumbnailRenderingPolicyReady == true)")
        smokePrint("SMOKE interactionProbePassed=\(interactionProbe?.passed == true)")
        smokePrint("SMOKE interactionProbe=\(interactionProbe?.diagnostics ?? "unavailable")")
        smokePrint("SMOKE panelResizable=\(panelController?.isResizable == true)")
        smokePrint("SMOKE panelUsesNormalWindowLevel=\(panelController?.usesNormalWindowLevel == true)")
        smokePrint("SMOKE layout=\(panelController?.layoutDiagnostics ?? "unavailable")")
        smokePrint("SMOKE placementCalculationCount=\(placementCount)")
        smokePrint("SMOKE toolbarControlCount=\(panelController?.toolbarControlCount ?? 0)")
        smokePrint("SMOKE panelHidden=\(hidden)")
        smokePrint("SMOKE browserPathLoaded=\(browserSnapshot.currentDirectoryURL.path == fixtureURL.path)")
        smokePrint("SMOKE browserFixtureEnumerated=\(browserSnapshot.itemNames.contains("alpha.txt"))")
        smokePrint("SMOKE browserSelectionClearedOnTeardown=\(browserSnapshot.selectedItemName == nil)")
        smokePrint("SMOKE browserConflictDefaultSkip=\(browserSnapshot.lastOperationStatus == .skipped)")
        smokePrint("SMOKE savedLocationRoundTrip=\(browserSnapshot.savedLocationNames.contains("Fixture Renamed"))")
        smokePrint("SMOKE previewTeardownCount=\(browserSnapshot.teardownCount >= 1)")
        smokePrint("SMOKE lifecycleObserversStopped=\(browserSnapshot.lifecycleDiagnostics.activeVisibleDirectoryObserverCount == 0 && browserSnapshot.lifecycleDiagnostics.activeVolumeObserverCount == 0)")
        smokePrint("SMOKE lifecycleTimersZero=\(browserSnapshot.lifecycleDiagnostics.timerCount == 0)")
        smokePrint("SMOKE lifecyclePostCloseCallbacksZero=\(browserSnapshot.lifecycleDiagnostics.postCloseCallbackCount == 0)")
        smokePrint(PanelTimingMetrics(
            warmLatencyMs: warmLatencyMs,
            coldLatencyMs: coldLatencyMs,
            rssBytes: ProcessMetrics.residentMemoryBytes()
        ).machineReadableSummary)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    private func runPerformanceProbe() async {
        let fixtureURL = ApplicationPaths.performanceFixtureURL()
        let visibleExpected = Int(ProcessInfo.processInfo.environment["PATHSHELF_PERF_VISIBLE"] ?? "1000") ?? 1000
        let savedExpected = Int(ProcessInfo.processInfo.environment["PATHSHELF_PERF_SAVED"] ?? "10") ?? 10
        let loadedPlacement = invocationController?.settings.panelPlacement.mode ?? .cursorAdjacent
        var warmSamples: [Double] = []

        let shellColdStart = PerformanceProbeClock.launchDateOverride() ?? appProcessProbeStart
        let coldSnapshot = await panelController?.showAndWaitForInteractiveProbe(
            mode: loadedPlacement,
            cursor: NSEvent.mouseLocation,
            screens: NSScreen.screens
        ) ?? BrowserSnapshot(
            currentDirectoryURL: fixtureURL,
            itemNames: [],
            selectedItemName: nil,
            savedLocationNames: [],
            availability: .unavailable(.unavailable, fixtureURL.path),
            lastOperationStatus: nil,
            lastErrorMessage: "performance probe did not run",
            isLoading: false,
            generation: 0,
            teardownCount: 0
        )
        let interactiveDate = Date()
        let coldMs = interactiveDate.timeIntervalSince(shellColdStart) * 1_000.0
        let appColdMs = interactiveDate.timeIntervalSince(appProcessProbeStart) * 1_000.0

        for _ in 0..<20 {
            panelController?.hide()
            let start = DispatchTime.now()
            _ = await panelController?.showAndWaitForInteractiveProbe(
                mode: loadedPlacement,
                cursor: NSEvent.mouseLocation,
                screens: NSScreen.screens,
                useCachedItems: true
            )
            warmSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
        }
        panelController?.hide()

        let sorted = warmSamples.sorted()
        let index = max(0, min(sorted.count - 1, Int(ceil(0.95 * Double(sorted.count))) - 1))
        let warmP95 = sorted[index]
        smokePrint("PERF cold_ms=\(String(format: "%.3f", coldMs)) app_cold_ms=\(String(format: "%.3f", appColdMs)) warm_p95_ms=\(String(format: "%.3f", warmP95)) warm_samples=\(warmSamples.count) phys_footprint_bytes=\(ProcessMetrics.physicalFootprintBytes()) rss_bytes=\(ProcessMetrics.residentMemoryBytes()) visible_items=\(coldSnapshot.itemNames.count) saved_locations=\(coldSnapshot.savedLocationNames.count) expected_visible_items=\(visibleExpected) expected_saved_locations=\(savedExpected) selected_item_ready=\(coldSnapshot.selectedItemName != nil) definition=cold_shell_launch_to_first_selectable_row_app_cold_recorded_warm_invocation_to_first_selectable_row")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    private func prepareSmokeFixture(at fixtureURL: URL) throws {
        try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: fixtureURL.appendingPathComponent("alpha.txt"))
        try Data("<!doctype html><html><body><h1>Quick Look HTML</h1></body></html>".utf8)
            .write(to: fixtureURL.appendingPathComponent("preview.html"))
        try FileManager.default.createDirectory(
            at: fixtureURL.appendingPathComponent("Existing", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func smokePrint(_ message: String) {
        print(message)
        fflush(stdout)
    }
}

final class TerminationSignalHandler {
    private let source: DispatchSourceSignal

    private init(source: DispatchSourceSignal) {
        self.source = source
    }

    static func install(onTerminate: @escaping () -> Void) -> TerminationSignalHandler {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler(handler: onTerminate)
        source.resume()
        return TerminationSignalHandler(source: source)
    }

    deinit {
        source.cancel()
    }
}

enum ApplicationPaths {
    static func settingsURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["PATHSHELF_SETTINGS_PATH"],
           overridePath.isEmpty == false {
            return URL(fileURLWithPath: overridePath)
        }

        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL
            .appendingPathComponent("PathShelf", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    static func bookmarksURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["PATHSHELF_BOOKMARKS_PATH"],
           overridePath.isEmpty == false {
            return URL(fileURLWithPath: overridePath)
        }

        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL
            .appendingPathComponent("PathShelf", isDirectory: true)
            .appendingPathComponent("bookmarks.json", isDirectory: false)
    }

    static func favoriteGroupsURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["PATHSHELF_GROUPS_PATH"],
           overridePath.isEmpty == false {
            return URL(fileURLWithPath: overridePath)
        }
        return bookmarksURL()
            .deletingLastPathComponent()
            .appendingPathComponent("favorite-groups.json", isDirectory: false)
    }

    static func smokeFixtureURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["PATHSHELF_SMOKE_FIXTURE"],
           overridePath.isEmpty == false {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("PathShelfSmoke", isDirectory: true)
    }

    static func performanceFixtureURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["PATHSHELF_PERF_FIXTURE"],
           overridePath.isEmpty == false {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        return smokeFixtureURL()
    }
}

enum MainMenuFactory {
    static func makeMainMenu(commandTarget: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.title = "PathShelf"
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Toggle Panel",
            action: #selector(PathShelfApp.togglePanelFromMenu(_:)),
            keyEquivalent: ""
        ).target = commandTarget
        appMenu.addItem(
            withTitle: "Settings...",
            action: #selector(PathShelfApp.openSettingsFromMenu(_:)),
            keyEquivalent: ","
        ).target = commandTarget
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit PathShelf",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "File"
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(PathShelfApp.closeActiveWindowFromMenu(_:)),
            keyEquivalent: "w"
        ).target = commandTarget
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        return mainMenu
    }
}

@MainActor
final class FloatingPanelController {
    private let model: FileBrowserModel
    private let workspaceService: WorkspaceActionService
    private let thumbnailService: ThumbnailService
    private let settingsStore: SettingsStore
    private let quickLookCoordinator: QuickLookPanelCoordinator
    private let onVisibilityChanged: (Bool) -> Void
    private var panel: NSPanel?
    private var focusView: PanelFocusView?
    private var contentView: PanelContentView?
    private(set) var placementCalculationCount = 0
    private(set) var lastSelectedVisibleFrame: CGRect?

    init(
        model: FileBrowserModel,
        workspaceService: WorkspaceActionService,
        thumbnailService: ThumbnailService,
        settingsStore: SettingsStore,
        quickLookCoordinator: QuickLookPanelCoordinator,
        onVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.model = model
        self.workspaceService = workspaceService
        self.thumbnailService = thumbnailService
        self.settingsStore = settingsStore
        self.quickLookCoordinator = quickLookCoordinator
        self.onVisibilityChanged = onVisibilityChanged
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    var hasKeyboardFocus: Bool {
        guard let focusView else {
            return false
        }
        return panel?.firstResponder === focusView
    }

    var isKeyWindow: Bool {
        panel?.isKeyWindow == true
    }

    func toggle(mode: PanelPlacementMode, cursor: CGPoint, screens: [NSScreen]) {
        if isPanelVisible {
            hide()
        } else {
            show(mode: mode, cursor: cursor, screens: screens)
        }
    }

    func show(mode: PanelPlacementMode, cursor: CGPoint, screens: [NSScreen]) {
        let signpostID = LocalDiagnostics.signposter.makeSignpostID()
        let state = LocalDiagnostics.signposter.beginInterval("panel_invocation_to_visible", id: signpostID)
        onVisibilityChanged(true)
        let panel = preparePanel(mode: mode, cursor: cursor, screens: screens)
        contentView?.start()
        panel.makeKeyAndOrderFront(nil)
        if let focusView {
            panel.makeFirstResponder(focusView)
        }
        NSApp.activate(ignoringOtherApps: true)
        LocalDiagnostics.signposter.endInterval("panel_invocation_to_visible", state)
        LocalDiagnostics.state("panel visible")
    }

    func hide() {
        let signpostID = LocalDiagnostics.signposter.makeSignpostID()
        let state = LocalDiagnostics.signposter.beginInterval("panel_hide_teardown", id: signpostID)
        contentView?.prepareForHide()
        panel?.orderOut(nil)
        onVisibilityChanged(false)
        LocalDiagnostics.signposter.endInterval("panel_hide_teardown", state)
        LocalDiagnostics.state("panel hidden")
    }

    func runSmokeBrowserProbe(fixtureURL: URL) async -> BrowserSnapshot {
        let panel = panel ?? makePanel()
        self.panel = panel
        contentView?.start()
        return await contentView?.runSmokeActions(fixtureURL: fixtureURL) ?? model.snapshot
    }

    func runColdInteractiveProbe() async -> BrowserSnapshot {
        let panel = panel ?? makePanel()
        self.panel = panel
        return await contentView?.runColdInteractiveProbe() ?? model.snapshot
    }

    func runInteractionProbe() async -> (passed: Bool, diagnostics: String) {
        await contentView?.runInteractionProbe() ?? (false, "unavailable")
    }

    func showAndWaitForInteractiveProbe(
        mode: PanelPlacementMode,
        cursor: CGPoint,
        screens: [NSScreen],
        useCachedItems: Bool = false
    ) async -> BrowserSnapshot {
        let panel = preparePanel(mode: mode, cursor: cursor, screens: screens)
        panel.makeKeyAndOrderFront(nil)
        if let focusView {
            panel.makeFirstResponder(focusView)
        }
        if useCachedItems {
            return contentView?.resumeCachedInteractive() ?? model.snapshot
        }
        return await contentView?.startAndWaitForInteractive() ?? model.snapshot
    }

    func grantFolderAccess(to url: URL) throws {
        try model.addSavedLocation(url: url)
        contentView?.refreshSavedLocations()
    }

    var toolbarControlCount: Int {
        contentView?.toolbarControlCount ?? 0
    }

    var layoutDiagnostics: String {
        contentView?.layoutDiagnostics ?? "unavailable"
    }

    var isLayoutReady: Bool {
        contentView?.isLayoutReady == true
    }

    var areInteractionsReady: Bool {
        contentView?.areInteractionsReady == true
    }

    var thumbnailRenderingPolicyReady: Bool {
        contentView?.thumbnailRenderingPolicyReady == true
    }

    var isResizable: Bool {
        panel?.styleMask.contains(.resizable) == true
    }

    var usesNormalWindowLevel: Bool {
        panel?.level == .normal
    }

    private func preparePanel(mode: PanelPlacementMode, cursor: CGPoint, screens: [NSScreen]) -> NSPanel {
        let panel = panel ?? makePanel()
        self.panel = panel
        let screen = screenContaining(cursor, screens: screens) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let requestedSize = CGSize(
            width: min(panel.frame.width, max(720, visibleFrame.width - 24)),
            height: min(panel.frame.height, max(480, visibleFrame.height - 24))
        )
        let calculator = PanelPlacementCalculator(panelSize: requestedSize)
        placementCalculationCount += 1
        lastSelectedVisibleFrame = visibleFrame
        panel.setFrame(
            calculator.frame(mode: mode, cursor: cursor, visibleFrame: visibleFrame),
            display: true
        )
        return panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 1080, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "PathShelf"
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentMinSize = CGSize(width: 800, height: 460)
        let contentView = PanelContentView(
            model: model,
            workspaceService: workspaceService,
            thumbnailService: thumbnailService,
            settingsStore: settingsStore,
            quickLookCoordinator: quickLookCoordinator,
            onEscape: { [weak self] in
            self?.hide()
        })
        focusView = contentView.focusView
        self.contentView = contentView
        panel.contentView = contentView
        return panel
    }

    private func screenContaining(_ point: CGPoint, screens: [NSScreen]) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
    }
}

private enum FolderAccessGrantError: Error, CustomStringConvertible {
    case panelUnavailable

    var description: String {
        "The file panel is not ready. Reopen PathShelf and try again."
    }
}

enum PerformanceProbeClock {
    static func launchDateOverride() -> Date? {
        guard let raw = ProcessInfo.processInfo.environment["PATHSHELF_PROCESS_START_NS"],
              let nanoseconds = Double(raw) else {
            return nil
        }
        return Date(timeIntervalSince1970: nanoseconds / 1_000_000_000.0)
    }
}

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem

    var isReady: Bool {
        statusItem.button != nil && statusItem.menu != nil
    }

    var hasVisibleIcon: Bool {
        guard let button = statusItem.button else {
            return false
        }
        return button.image != nil || button.title.isEmpty == false
    }

    init(togglePanel: @escaping () -> Void, openSettings: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "PathShelf") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
        } else {
            statusItem.button?.title = "OFP"
        }
        statusItem.button?.toolTip = "PathShelf"
        let menu = NSMenu()
        menu.addItem(StatusItemAction(title: "Toggle Panel", actionHandler: togglePanel))
        menu.addItem(StatusItemAction(title: "Settings...", actionHandler: openSettings))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit PathShelf",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }
}

final class StatusItemAction: NSMenuItem {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func runAction() {
        actionHandler()
    }
}

final class HotKeyEventDispatcher {
    enum Error: Swift.Error {
        case installFailed(OSStatus)
    }

    private var handlerRef: EventHandlerRef?
    private let onHotKeyPressed: () -> Void

    init(onHotKeyPressed: @escaping () -> Void) {
        self.onHotKeyPressed = onHotKeyPressed
    }

    func install() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let reference = HotKeyDispatcherReference(pointer: userData)
                DispatchQueue.main.async {
                    let dispatcher = Unmanaged<HotKeyEventDispatcher>
                        .fromOpaque(reference.pointer)
                        .takeUnretainedValue()
                    dispatcher.onHotKeyPressed()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr else {
            throw Error.installFailed(status)
        }
    }

    deinit {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}

private struct HotKeyDispatcherReference: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
}
