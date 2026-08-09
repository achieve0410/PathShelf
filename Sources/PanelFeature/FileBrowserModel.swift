import FileAccess
import FileOperations
import Foundation
import PreviewFeature

public enum BrowserAvailabilityState: Equatable, Sendable {
    case available
    case unavailable(SavedLocation.Availability, String)
}

public struct BrowserSavedLocation: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var originalPath: String
    public var availability: SavedLocation.Availability

    public init(location: SavedLocation) {
        self.id = location.id
        self.displayName = location.displayName
        self.originalPath = location.bookmark.originalPath
        self.availability = location.availability
    }
}

public enum FavoriteSidebarItem: Equatable, Sendable {
    case group(FavoriteGroup?)
    case location(SavedLocation)
}

public struct BrowserSnapshot: Equatable, Sendable {
    public var currentDirectoryURL: URL
    public var itemNames: [String]
    public var selectedItemName: String?
    public var savedLocationNames: [String]
    public var availability: BrowserAvailabilityState
    public var lastOperationStatus: FileOperationStatus?
    public var lastErrorMessage: String?
    public var isLoading: Bool
    public var generation: Int
    public var teardownCount: Int
    public var lifecycleDiagnostics: LifecycleDiagnosticsSnapshot

    public init(
        currentDirectoryURL: URL,
        itemNames: [String],
        selectedItemName: String?,
        savedLocationNames: [String],
        availability: BrowserAvailabilityState,
        lastOperationStatus: FileOperationStatus?,
        lastErrorMessage: String?,
        isLoading: Bool,
        generation: Int,
        teardownCount: Int,
        lifecycleDiagnostics: LifecycleDiagnosticsSnapshot = LifecycleDiagnosticsSnapshot()
    ) {
        self.currentDirectoryURL = currentDirectoryURL
        self.itemNames = itemNames
        self.selectedItemName = selectedItemName
        self.savedLocationNames = savedLocationNames
        self.availability = availability
        self.lastOperationStatus = lastOperationStatus
        self.lastErrorMessage = lastErrorMessage
        self.isLoading = isLoading
        self.generation = generation
        self.teardownCount = teardownCount
        self.lifecycleDiagnostics = lifecycleDiagnostics
    }
}

public enum FileBrowserError: Error, Equatable, Sendable, CustomStringConvertible {
    case noSelection
    case selectedLocationUnavailable(SavedLocation.Availability, String)
    case savedLocationMissing(UUID)
    case openPanelCancelled
    case unsupportedSavedLocation(String)
    case favoriteGroupMissing(UUID)
    case invalidFavoriteGroupName

    public var description: String {
        switch self {
        case .noSelection:
            return "No item is selected."
        case .selectedLocationUnavailable(let availability, let path):
            return "Saved location is \(availability.rawValue): \(path)"
        case .savedLocationMissing(let id):
            return "Saved location is missing: \(id.uuidString)"
        case .openPanelCancelled:
            return "Folder selection was cancelled."
        case .unsupportedSavedLocation(let path):
            return "Saved location is outside the supported local home or external volume scope: \(path)"
        case .favoriteGroupMissing(let id):
            return "Favorite group is missing: \(id.uuidString)"
        case .invalidFavoriteGroupName:
            return "Favorite group name cannot be empty."
        }
    }
}

public struct DropOperationIntent: Equatable, Sendable {
    public var allowsMove: Bool
    public var explicitMove: Bool

    public init(allowsMove: Bool, explicitMove: Bool) {
        self.allowsMove = allowsMove
        self.explicitMove = explicitMove
    }
}

public enum DropOperationResolver {
    public static func shouldMove(_ intent: DropOperationIntent) -> Bool {
        intent.allowsMove && intent.explicitMove
    }
}

public protocol FolderSelectionProviding: Sendable {
    @MainActor func selectFolder() async throws -> URL
}

public struct FileBrowserEnvironment: Sendable {
    public var homeDirectory: @Sendable () -> URL
    public var initialDirectory: @Sendable () -> URL
    public var enumerate: @Sendable (URL) async throws -> DirectoryEnumerationResult
    public var loadSavedLocations: @Sendable () throws -> [SavedLocation]
    public var saveSavedLocations: @Sendable ([SavedLocation]) throws -> Void
    public var loadFavoriteGroups: @Sendable () throws -> [FavoriteGroup]
    public var saveFavoriteGroups: @Sendable ([FavoriteGroup]) throws -> Void
    public var makeBookmark: @Sendable (URL) throws -> PersistedBookmark
    public var resolveBookmark: @Sendable (PersistedBookmark) -> BookmarkResolution
    public var fileOperationService: FileOperationService
    public var previewController: QuickLookPreviewController?
    public var closeSecurityScopedURL: @Sendable (SecurityScopedURL) -> Void
    public var visibleDirectoryMonitor: VisibleDirectoryMonitor?
    public var volumeEventObserver: VolumeEventObserver?
    public var externalLocationProbe: ExternalLocationProbe
    public var navigationPolicy: @Sendable (URL) -> NavigationAccessPolicy
    public var lifecycleDiagnostics: LifecycleDiagnostics

    public init(
        homeDirectory: @escaping @Sendable () -> URL = { HomeDirectoryProvider().homeDirectory },
        initialDirectory: (@Sendable () -> URL)? = nil,
        enumerate: @escaping @Sendable (URL) async throws -> DirectoryEnumerationResult = { url in
            try await DirectoryEnumerator().enumerate(url)
        },
        loadSavedLocations: @escaping @Sendable () throws -> [SavedLocation],
        saveSavedLocations: @escaping @Sendable ([SavedLocation]) throws -> Void,
        loadFavoriteGroups: @escaping @Sendable () throws -> [FavoriteGroup] = { [] },
        saveFavoriteGroups: @escaping @Sendable ([FavoriteGroup]) throws -> Void = { _ in },
        makeBookmark: @escaping @Sendable (URL) throws -> PersistedBookmark,
        resolveBookmark: @escaping @Sendable (PersistedBookmark) -> BookmarkResolution,
        fileOperationService: FileOperationService = FileOperationService(),
        previewController: QuickLookPreviewController? = nil,
        closeSecurityScopedURL: @escaping @Sendable (SecurityScopedURL) -> Void = { $0.close() },
        visibleDirectoryMonitor: VisibleDirectoryMonitor? = nil,
        volumeEventObserver: VolumeEventObserver? = nil,
        externalLocationProbe: ExternalLocationProbe = .live,
        navigationPolicy: @escaping @Sendable (URL) -> NavigationAccessPolicy = { home in
            NavigationAccessPolicy(homeRoot: home)
        },
        lifecycleDiagnostics: LifecycleDiagnostics = LifecycleDiagnostics()
    ) {
        self.homeDirectory = homeDirectory
        self.initialDirectory = initialDirectory ?? homeDirectory
        self.enumerate = enumerate
        self.loadSavedLocations = loadSavedLocations
        self.saveSavedLocations = saveSavedLocations
        self.loadFavoriteGroups = loadFavoriteGroups
        self.saveFavoriteGroups = saveFavoriteGroups
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
        self.fileOperationService = fileOperationService
        self.previewController = previewController
        self.closeSecurityScopedURL = closeSecurityScopedURL
        self.visibleDirectoryMonitor = visibleDirectoryMonitor
        self.volumeEventObserver = volumeEventObserver
        self.externalLocationProbe = externalLocationProbe
        self.navigationPolicy = navigationPolicy
        self.lifecycleDiagnostics = lifecycleDiagnostics
    }
}

@MainActor
public final class FileBrowserModel {
    public private(set) var currentDirectoryURL: URL
    public private(set) var items: [FileItem] = []
    public private(set) var savedLocations: [SavedLocation] = []
    public private(set) var favoriteGroups: [FavoriteGroup] = []
    public private(set) var availability: BrowserAvailabilityState = .available
    public private(set) var selectedIndex: Int?
    public private(set) var isLoading = false
    public private(set) var lastOperationOutcome: FileOperationOutcome?
    public private(set) var lastErrorMessage: String?
    public private(set) var generation = 0
    public private(set) var teardownCount = 0
    public private(set) var sortOrder: FileSortOrder = .kindThenName

    private let environment: FileBrowserEnvironment
    private var history: [URL] = []
    private let configuredInitialRoot: URL?
    private var activeScopedURL: SecurityScopedURL?
    private var lifecycleIsActive = false
    private var directoryRefreshInFlight = false
    private var pendingDirectoryEvent = false

    public init(environment: FileBrowserEnvironment) {
        self.environment = environment
        let homeDirectory = environment.homeDirectory().standardizedFileURL
        let initialDirectory = environment.initialDirectory().standardizedFileURL
        self.currentDirectoryURL = initialDirectory
        self.configuredInitialRoot = initialDirectory == homeDirectory ? nil : initialDirectory
    }

    deinit {
        activeScopedURL?.close()
        environment.visibleDirectoryMonitor?.stop()
        environment.volumeEventObserver?.stop()
    }

    public var selectedItem: FileItem? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else {
            return nil
        }
        return items[selectedIndex]
    }

    public func loadInitialState() async {
        await loadSavedLocations()
        loadFavoriteGroups()
        await navigate(to: environment.initialDirectory(), recordHistory: false)
    }

    public func reload() async {
        await navigate(to: currentDirectoryURL, recordHistory: false)
    }

    public func startLifecycleMonitoring() {
        guard lifecycleIsActive == false else {
            return
        }
        lifecycleIsActive = true
        environment.visibleDirectoryMonitor?.start(root: currentDirectoryURL) { [weak self] eventGeneration, event in
            Task { @MainActor [weak self] in
                await self?.handleVisibleDirectoryEvent(generation: eventGeneration, event: event)
            }
        }
        environment.volumeEventObserver?.start { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.handleVolumeEvent(event)
            }
        }
    }

    public func stopLifecycleMonitoring() {
        lifecycleIsActive = false
        environment.visibleDirectoryMonitor?.stop()
        environment.volumeEventObserver?.stop()
    }

    public func setActiveThumbnailCount(_ count: Int) {
        environment.lifecycleDiagnostics.setActiveThumbnailCount(count)
    }

    public func navigateHome() async {
        await navigate(to: environment.homeDirectory(), recordHistory: true)
    }

    public func navigateToPathBarLocation(_ directoryURL: URL) async {
        guard openSecurityScopeForSavedLocationIfNeeded(containing: directoryURL) else {
            lastErrorMessage = "Access is unavailable for \(directoryURL.path)"
            return
        }
        await navigate(to: directoryURL, recordHistory: true)
    }

    public func navigateBack() async {
        guard let previous = history.popLast() else {
            return
        }
        guard openSecurityScopeForSavedLocationIfNeeded(containing: previous) else {
            return
        }
        await navigate(to: previous, recordHistory: false)
    }

    public func navigateUp() async {
        let navigationRoot = activeScopedURL?.url
            ?? configuredInitialRoot.flatMap { root in
                accessPolicy.isInsideScopedRoot(currentDirectoryURL, scopedRoot: root) ? root : nil
            }
        guard let parent = accessPolicy.parentForUpNavigation(
            from: currentDirectoryURL,
            scopedRoot: navigationRoot
        ) else {
            return
        }
        await navigate(to: parent, recordHistory: true)
    }

    public func openSelectionOrEnterDirectory() async -> URL? {
        guard let item = selectedItem else {
            lastErrorMessage = FileBrowserError.noSelection.description
            return nil
        }
        if item.kind == .directory {
            await navigate(to: item.url, recordHistory: true)
            return nil
        }
        return item.url
    }

    public func select(index: Int?) {
        if let index, items.indices.contains(index) {
            selectedIndex = index
        } else {
            selectedIndex = nil
        }
    }

    public func selectFirstItem(named name: String) {
        selectedIndex = items.firstIndex { $0.name == name }
    }

    public func setSortOrder(_ order: FileSortOrder) {
        let selectedURL = selectedItem?.url
        sortOrder = order
        items = order.sorted(items)
        selectedIndex = selectedURL.flatMap { selectedURL in
            items.firstIndex { $0.url == selectedURL }
        }
    }

    public func addSavedLocation(url: URL, displayName: String? = nil) throws {
        do {
            try accessPolicy.validateSavedLocation(url)
        } catch NavigationAccessPolicyError.unsupportedSavedLocation(let path) {
            throw FileBrowserError.unsupportedSavedLocation(path)
        }
        let bookmark = try environment.makeBookmark(url)
        let metadata = environment.externalLocationProbe.metadata(for: url)
        let location = SavedLocation(
            displayName: displayName ?? url.lastPathComponent,
            bookmark: bookmark,
            sortOrder: savedLocations.count,
            availability: ExternalLocationStateResolver.availability(
                current: .available,
                resolution: BookmarkResolution(
                    scopedURL: nil,
                    originalPath: url.path,
                    isStale: false,
                    availability: .available,
                    error: nil
                ),
                metadata: metadata,
                lastKnownExternalKind: nil,
                markRecovered: false
            ),
            lastKnownExternalKind: metadata.externalKind,
            groupID: nil
        )
        var candidate = savedLocations
        candidate.append(location)
        try persistSavedLocations(candidate)
        savedLocations = normalizedSavedLocations(candidate)
    }

    public func addSavedLocation(from provider: FolderSelectionProviding) async throws {
        let url = try await provider.selectFolder()
        try addSavedLocation(url: url)
    }

    public func renameSavedLocation(id: UUID, to displayName: String) throws {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.savedLocationMissing(id)
        }
        var candidate = savedLocations
        candidate[index].displayName = displayName
        try persistSavedLocations(candidate)
        savedLocations = normalizedSavedLocations(candidate)
    }

    public func moveSavedLocation(id: UUID, direction: Int) throws {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.savedLocationMissing(id)
        }
        let groupID = savedLocations[index].groupID
        let siblingIDs = locations(in: groupID).map(\.id)
        guard let siblingIndex = siblingIDs.firstIndex(of: id) else {
            return
        }
        let target = siblingIndex + direction
        guard siblingIDs.indices.contains(target) else {
            return
        }
        try moveSavedLocation(id: id, toGroup: groupID, before: direction > 0
            ? siblingIDs.indices.contains(target + 1) ? siblingIDs[target + 1] : nil
            : siblingIDs[target])
    }

    public func addFavoriteGroup(named name: String) throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw FileBrowserError.invalidFavoriteGroupName
        }
        let group = FavoriteGroup(name: trimmed, sortOrder: favoriteGroups.count)
        var candidate = favoriteGroups
        candidate.append(group)
        try environment.saveFavoriteGroups(normalizedFavoriteGroups(candidate))
        favoriteGroups = normalizedFavoriteGroups(candidate)
        return group.id
    }

    public func renameFavoriteGroup(id: UUID, to name: String) throws {
        guard let index = favoriteGroups.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.favoriteGroupMissing(id)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw FileBrowserError.invalidFavoriteGroupName
        }
        var candidate = favoriteGroups
        candidate[index].name = trimmed
        try environment.saveFavoriteGroups(normalizedFavoriteGroups(candidate))
        favoriteGroups = normalizedFavoriteGroups(candidate)
    }

    public func updateFavoriteGroupIcon(id: UUID, iconName: String) throws {
        guard let index = favoriteGroups.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.favoriteGroupMissing(id)
        }
        var candidate = favoriteGroups
        candidate[index].iconName = iconName
        try environment.saveFavoriteGroups(normalizedFavoriteGroups(candidate))
        favoriteGroups = normalizedFavoriteGroups(candidate)
    }

    public func removeFavoriteGroup(id: UUID) throws {
        guard favoriteGroups.contains(where: { $0.id == id }) else {
            throw FileBrowserError.favoriteGroupMissing(id)
        }
        let previousLocations = savedLocations
        var locationCandidate = savedLocations
        for index in locationCandidate.indices where locationCandidate[index].groupID == id {
            locationCandidate[index].groupID = nil
        }
        locationCandidate = normalizedSavedLocations(locationCandidate)
        var groupCandidate = favoriteGroups.filter { $0.id != id }
        groupCandidate = normalizedFavoriteGroups(groupCandidate)
        try persistSavedLocations(locationCandidate)
        do {
            try environment.saveFavoriteGroups(groupCandidate)
        } catch {
            try? persistSavedLocations(previousLocations)
            throw error
        }
        savedLocations = locationCandidate
        favoriteGroups = groupCandidate
    }

    public func moveFavoriteGroup(id: UUID, before targetID: UUID?) throws {
        guard let sourceIndex = favoriteGroups.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.favoriteGroupMissing(id)
        }
        guard targetID != id else {
            return
        }
        var candidate = favoriteGroups
        let group = candidate.remove(at: sourceIndex)
        let targetIndex = targetID.flatMap { targetID in
            candidate.firstIndex(where: { $0.id == targetID })
        } ?? candidate.endIndex
        candidate.insert(group, at: targetIndex)
        candidate = normalizedFavoriteGroups(candidate)
        try environment.saveFavoriteGroups(candidate)
        favoriteGroups = candidate
    }

    public func moveSavedLocation(
        id: UUID,
        toGroup groupID: UUID?,
        before targetID: UUID?
    ) throws {
        guard let sourceIndex = savedLocations.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.savedLocationMissing(id)
        }
        guard targetID != id else {
            return
        }
        if let groupID, favoriteGroups.contains(where: { $0.id == groupID }) == false {
            throw FileBrowserError.favoriteGroupMissing(groupID)
        }
        var candidate = savedLocations
        candidate[sourceIndex].groupID = groupID
        let moved = candidate.remove(at: sourceIndex)
        let targetIndex = targetID.flatMap { targetID in
            candidate.firstIndex(where: { $0.id == targetID })
        } ?? candidate.endIndex
        candidate.insert(moved, at: targetIndex)
        try persistSavedLocations(candidate)
        savedLocations = normalizedSavedLocations(candidate)
    }

    public func removeSavedLocation(id: UUID) throws {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.savedLocationMissing(id)
        }
        var candidate = savedLocations
        candidate.remove(at: index)
        try persistSavedLocations(candidate)
        savedLocations = normalizedSavedLocations(candidate)
    }

    public func navigateToSavedLocation(id: UUID) async throws {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.savedLocationMissing(id)
        }
        let scopedURL = try openSecurityScopeForSavedLocation(at: index)
        await navigate(to: scopedURL.url, recordHistory: true)
    }

    public func retrySavedLocation(id: UUID) async throws {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else {
            throw FileBrowserError.savedLocationMissing(id)
        }
        try recoverSavedLocation(at: index, markRecovered: true)
    }

    @discardableResult
    public func createFolder(named name: String, conflictPolicy: ConflictPolicy = .skip) async -> FileOperationOutcome {
        let outcome = await environment.fileOperationService.createFolder(
            named: name,
            in: currentDirectoryURL,
            conflictPolicy: conflictPolicy
        )
        await recordAndRefresh(outcome)
        return outcome
    }

    @discardableResult
    public func renameSelection(to name: String, conflictPolicy: ConflictPolicy = .skip) async -> FileOperationOutcome? {
        guard let item = selectedItem else {
            lastErrorMessage = FileBrowserError.noSelection.description
            return nil
        }
        let outcome = await environment.fileOperationService.rename(
            item.url,
            to: name,
            conflictPolicy: conflictPolicy
        )
        await recordAndRefresh(outcome)
        return outcome
    }

    @discardableResult
    public func copySelection(to destinationDirectoryURL: URL, conflictPolicy: ConflictPolicy = .skip) async -> FileOperationOutcome? {
        guard let item = selectedItem else {
            lastErrorMessage = FileBrowserError.noSelection.description
            return nil
        }
        let outcome = await environment.fileOperationService.copy(
            item.url,
            to: destinationDirectoryURL,
            conflictPolicy: conflictPolicy
        )
        await recordAndRefresh(outcome)
        return outcome
    }

    @discardableResult
    public func moveSelection(to destinationDirectoryURL: URL, conflictPolicy: ConflictPolicy = .skip) async -> FileOperationOutcome? {
        guard let item = selectedItem else {
            lastErrorMessage = FileBrowserError.noSelection.description
            return nil
        }
        let outcome = await environment.fileOperationService.move(
            item.url,
            to: destinationDirectoryURL,
            conflictPolicy: conflictPolicy
        )
        await recordAndRefresh(outcome)
        return outcome
    }

    @discardableResult
    public func trashSelection(confirm: Bool) async -> FileOperationOutcome? {
        guard confirm else {
            lastErrorMessage = "Trash requires confirmation."
            return nil
        }
        guard let item = selectedItem else {
            lastErrorMessage = FileBrowserError.noSelection.description
            return nil
        }
        let outcome = await environment.fileOperationService.trash(item.url)
        await recordAndRefresh(outcome)
        return outcome
    }

    @discardableResult
    public func performFileOperation(_ request: FileOperationRequest) async -> FileOperationOutcome {
        let outcome = await environment.fileOperationService.perform(request)
        await recordAndRefresh(outcome)
        return outcome
    }

    public func presentQuickLookForSelection() {
        guard let item = selectedItem else {
            lastErrorMessage = FileBrowserError.noSelection.description
            return
        }
        environment.previewController?.present(PreviewItem(url: item.url, displayName: item.name))
    }

    public func teardown() {
        stopLifecycleMonitoring()
        generation += 1
        teardownCount += 1
        selectedIndex = nil
        environment.previewController?.close()
        closeActiveScopedURL()
    }

    public var snapshot: BrowserSnapshot {
        BrowserSnapshot(
            currentDirectoryURL: currentDirectoryURL,
            itemNames: items.map(\.name),
            selectedItemName: selectedItem?.name,
            savedLocationNames: savedLocations.map(\.displayName),
            availability: availability,
            lastOperationStatus: lastOperationOutcome?.status,
            lastErrorMessage: lastErrorMessage,
            isLoading: isLoading,
            generation: generation,
            teardownCount: teardownCount,
            lifecycleDiagnostics: environment.lifecycleDiagnostics.snapshot
        )
    }

    public var browserSavedLocations: [BrowserSavedLocation] {
        savedLocations.map(BrowserSavedLocation.init(location:))
    }

    public var favoriteSidebarItems: [FavoriteSidebarItem] {
        let knownGroupIDs = Set(favoriteGroups.map(\.id))
        var result: [FavoriteSidebarItem] = [.group(nil)]
        let ungrouped = savedLocations
            .filter { location in
                guard let groupID = location.groupID else {
                    return true
                }
                return knownGroupIDs.contains(groupID) == false
            }
            .sorted(by: savedLocationSort)
        result.append(contentsOf: ungrouped.map(FavoriteSidebarItem.location))
        for group in favoriteGroups.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            result.append(.group(group))
            result.append(contentsOf: locations(in: group.id).map(FavoriteSidebarItem.location))
        }
        return result
    }

    private func loadSavedLocations() async {
        do {
            savedLocations = try environment.loadSavedLocations().sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
        } catch {
            lastErrorMessage = String(describing: error)
            savedLocations = []
        }
    }

    private func loadFavoriteGroups() {
        do {
            favoriteGroups = normalizedFavoriteGroups(try environment.loadFavoriteGroups())
        } catch {
            lastErrorMessage = String(describing: error)
            favoriteGroups = []
        }
    }

    private func navigate(to directoryURL: URL, recordHistory: Bool) async {
        let directoryURL = directoryURL.standardizedFileURL
        let previousURL = currentDirectoryURL
        closeActiveScopeIfNeeded(for: directoryURL)
        currentDirectoryURL = directoryURL
        availability = .available
        isLoading = true
        selectedIndex = nil
        generation += 1
        let requestGeneration = generation

        do {
            let result = try await environment.enumerate(directoryURL)
            guard requestGeneration == generation else {
                return
            }
            if recordHistory {
                history.append(previousURL)
            }
            items = sortOrder.sorted(result.items)
            lastErrorMessage = nil
            replaceVisibleDirectoryMonitorRoot()
        } catch {
            guard requestGeneration == generation else {
                return
            }
            items = []
            availability = .unavailable(.unavailable, directoryURL.path)
            lastErrorMessage = String(describing: error)
            replaceVisibleDirectoryMonitorRoot()
        }
        isLoading = false
    }

    private func replaceVisibleDirectoryMonitorRoot() {
        guard lifecycleIsActive else {
            return
        }
        environment.visibleDirectoryMonitor?.replaceRoot(currentDirectoryURL) { [weak self] eventGeneration, event in
            Task { @MainActor [weak self] in
                await self?.handleVisibleDirectoryEvent(generation: eventGeneration, event: event)
            }
        }
    }

    private func handleVisibleDirectoryEvent(generation eventGeneration: Int, event: DirectoryEvent) async {
        guard lifecycleIsActive,
              eventGeneration == environment.visibleDirectoryMonitor?.currentGeneration else {
            return
        }
        environment.lifecycleDiagnostics.uiMutationRecorded()

        if directoryRefreshInFlight {
            pendingDirectoryEvent = true
            return
        }

        directoryRefreshInFlight = true
        repeat {
            pendingDirectoryEvent = false
            await reload()
        } while pendingDirectoryEvent
        directoryRefreshInFlight = false
    }

    private func handleVolumeEvent(_ event: VolumeEvent) async {
        guard lifecycleIsActive else {
            return
        }
        environment.lifecycleDiagnostics.uiMutationRecorded()
        switch event.kind {
        case .unmounted:
            downgradeSavedLocationsDisconnectedByVolumeLoss(event.url)
        case .mounted, .renamed, .injected:
            await recoverUnavailableSavedLocations()
        }
    }

    private func recoverUnavailableSavedLocations() async {
        for index in savedLocations.indices {
            guard savedLocations[index].availability != .available else {
                continue
            }
            try? recoverSavedLocation(at: index, markRecovered: true)
        }
    }

    private func recoverSavedLocation(at index: Int, markRecovered: Bool) throws {
        let location = savedLocations[index]
        let resolution = environment.resolveBookmark(location.bookmark)
        let metadata = resolution.scopedURL.map { environment.externalLocationProbe.metadata(for: $0.url) }
        let nextAvailability = ExternalLocationStateResolver.availability(
            current: location.availability,
            resolution: resolution,
            metadata: metadata,
            lastKnownExternalKind: location.lastKnownExternalKind,
            markRecovered: markRecovered
        )
        if let scopedURL = resolution.scopedURL {
            environment.closeSecurityScopedURL(scopedURL)
        }

        var candidate = savedLocations
        candidate[index].availability = nextAvailability
        if let metadata {
            candidate[index].lastKnownExternalKind = metadata.externalKind
        }
        try persistSavedLocations(candidate)
        savedLocations = normalizedSavedLocations(candidate)
    }

    private func markRecoveredLocationUsable(id: UUID) {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }),
              savedLocations[index].availability == .recovered else {
            return
        }
        var candidate = savedLocations
        candidate[index].availability = .available
        if (try? persistSavedLocations(candidate)) != nil {
            savedLocations = normalizedSavedLocations(candidate)
        }
    }

    private func recordAndRefresh(_ outcome: FileOperationOutcome) async {
        lastOperationOutcome = outcome
        let operationErrorMessage = outcome.error?.description
        if let error = outcome.error {
            lastErrorMessage = error.description
        } else {
            lastErrorMessage = nil
        }
        if shouldRefresh(after: outcome) {
            await reload()
            if let operationErrorMessage {
                lastErrorMessage = operationErrorMessage
            }
        }
    }

    private func shouldRefresh(after outcome: FileOperationOutcome) -> Bool {
        switch outcome.status {
        case .success, .skipped, .partiallyFailed:
            return true
        case .failed:
            return false
        }
    }

    private func persistSavedLocations(_ locations: [SavedLocation]) throws {
        try environment.saveSavedLocations(normalizedSavedLocations(locations))
    }

    private func normalizedSavedLocations(_ locations: [SavedLocation]) -> [SavedLocation] {
        var normalized = locations
        let groupIDs = Set(normalized.map(\.groupID))
        for groupID in groupIDs {
            let indices = normalized.indices.filter { normalized[$0].groupID == groupID }
            for (sortOrder, index) in indices.enumerated() {
                normalized[index].sortOrder = sortOrder
            }
        }
        return normalized
    }

    private func normalizedFavoriteGroups(_ groups: [FavoriteGroup]) -> [FavoriteGroup] {
        var normalized = groups
        for index in normalized.indices {
            normalized[index].sortOrder = index
        }
        return normalized
    }

    private func locations(in groupID: UUID?) -> [SavedLocation] {
        savedLocations
            .filter { $0.groupID == groupID }
            .sorted(by: savedLocationSort)
    }

    private func savedLocationSort(_ lhs: SavedLocation, _ rhs: SavedLocation) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        return lhs.sortOrder < rhs.sortOrder
    }

    private var accessPolicy: NavigationAccessPolicy {
        environment.navigationPolicy(environment.homeDirectory())
    }

    private func openSecurityScopeForSavedLocationIfNeeded(containing targetURL: URL) -> Bool {
        if let activeScopedURL,
           accessPolicy.isInsideScopedRoot(targetURL, scopedRoot: activeScopedURL.url) {
            return true
        }
        guard let index = savedLocationIndex(containing: targetURL) else {
            return true
        }
        do {
            _ = try openSecurityScopeForSavedLocation(at: index)
            return true
        } catch {
            return false
        }
    }

    private func openSecurityScopeForSavedLocation(at index: Int) throws -> SecurityScopedURL {
        closeActiveScopedURL()
        let resolution = environment.resolveBookmark(savedLocations[index].bookmark)
        var candidate = savedLocations
        let metadata = resolution.scopedURL.map { environment.externalLocationProbe.metadata(for: $0.url) }
        candidate[index].availability = ExternalLocationStateResolver.availability(
            current: candidate[index].availability,
            resolution: resolution,
            metadata: metadata,
            lastKnownExternalKind: candidate[index].lastKnownExternalKind,
            markRecovered: false
        )
        if let metadata {
            candidate[index].lastKnownExternalKind = metadata.externalKind
        }
        if (try? persistSavedLocations(candidate)) != nil {
            savedLocations = normalizedSavedLocations(candidate)
        }

        guard ExternalLocationStateResolver.isUsable(candidate[index].availability),
              let scopedURL = resolution.scopedURL else {
            if let scopedURL = resolution.scopedURL {
                environment.closeSecurityScopedURL(scopedURL)
            }
            availability = .unavailable(candidate[index].availability, resolution.originalPath)
            items = []
            selectedIndex = nil
            let message = FileBrowserError.selectedLocationUnavailable(
                candidate[index].availability,
                resolution.originalPath
            ).description
            lastErrorMessage = message
            throw FileBrowserError.selectedLocationUnavailable(
                candidate[index].availability,
                resolution.originalPath
            )
        }

        activeScopedURL = scopedURL
        if candidate[index].availability == .recovered {
            markRecoveredLocationUsable(id: candidate[index].id)
        }
        return scopedURL
    }

    private func savedLocationIndex(containing targetURL: URL) -> Int? {
        let policy = accessPolicy
        return savedLocations.firstIndex { location in
            policy.isInsideScopedRoot(
                targetURL,
                scopedRoot: URL(fileURLWithPath: location.bookmark.originalPath, isDirectory: true)
            )
        }
    }

    private func closeActiveScopeIfNeeded(for targetURL: URL) {
        guard let activeScopedURL else {
            return
        }
        if accessPolicy.isInsideScopedRoot(targetURL, scopedRoot: activeScopedURL.url) {
            return
        }
        closeActiveScopedURL()
    }

    private func closeActiveScopedURL() {
        if let activeScopedURL {
            environment.closeSecurityScopedURL(activeScopedURL)
        }
        activeScopedURL = nil
    }

    private func downgradeSavedLocationsDisconnectedByVolumeLoss(_ volumeURL: URL?) {
        if let volumeURL,
           let activeScopedURL,
           accessPolicy.isInsideScopedRoot(activeScopedURL.url, scopedRoot: volumeURL) {
            closeActiveScopedURL()
        }
        invalidateCurrentDirectoryIfNeeded(forUnmounted: volumeURL)

        var candidate = savedLocations
        var changed = false

        for index in candidate.indices {
            let originalURL = URL(fileURLWithPath: candidate[index].bookmark.originalPath, isDirectory: true)
            let isOnUnmountedVolume = volumeURL.map {
                accessPolicy.isInsideScopedRoot(originalURL, scopedRoot: $0)
            } ?? true
            guard candidate[index].availability == .available,
                  let kind = candidate[index].lastKnownExternalKind,
                  kind == .removable || kind == .network,
                  isOnUnmountedVolume else {
                continue
            }

            candidate[index].availability = kind == .network ? .networkUnavailable : .disconnected
            changed = true
        }

        guard changed, (try? persistSavedLocations(candidate)) != nil else {
            return
        }
        savedLocations = normalizedSavedLocations(candidate)
    }

    private func invalidateCurrentDirectoryIfNeeded(forUnmounted volumeURL: URL?) {
        guard let volumeURL,
              accessPolicy.isInsideScopedRoot(currentDirectoryURL, scopedRoot: volumeURL) else {
            return
        }

        let locationKind = savedLocationIndex(containing: currentDirectoryURL).flatMap {
            savedLocations[$0].lastKnownExternalKind
        }
        let nextAvailability: SavedLocation.Availability = locationKind == .network
            ? .networkUnavailable
            : .disconnected
        availability = .unavailable(nextAvailability, currentDirectoryURL.path)
        items = []
        selectedIndex = nil
        isLoading = false
        generation += 1
        lastErrorMessage = FileBrowserError.selectedLocationUnavailable(
            nextAvailability,
            currentDirectoryURL.path
        ).description
        environment.visibleDirectoryMonitor?.stop()
    }
}
