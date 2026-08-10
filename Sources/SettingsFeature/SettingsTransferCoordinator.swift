import FileAccess
import Foundation

public struct SettingsTransferImportResult: Equatable, Sendable {
    public var settings: AppSettings
    public var favoriteGroups: [FavoriteGroup]
    public var savedLocations: [SavedLocation]
    public var unresolvedLocationCount: Int

    public init(
        settings: AppSettings,
        favoriteGroups: [FavoriteGroup],
        savedLocations: [SavedLocation],
        unresolvedLocationCount: Int
    ) {
        self.settings = settings
        self.favoriteGroups = favoriteGroups
        self.savedLocations = savedLocations
        self.unresolvedLocationCount = unresolvedLocationCount
    }
}

public enum SettingsTransferCoordinatorError: Error, Equatable, Sendable {
    case transfer(SettingsTransferError)
    case store(String)
    case transaction(ImportedSettingsCommitError)
}

public final class SettingsTransferCoordinator: @unchecked Sendable {
    private struct StoreRollbackError: Error, CustomStringConvertible {
        var failures: [String]

        var description: String {
            failures.joined(separator: "; ")
        }
    }

    private let invocationController: InvocationController
    private let bookmarkStore: BookmarkStore
    private let favoriteGroupStore: FavoriteGroupStore
    private let bookmarkService: SecurityScopedBookmarkService
    private let locationProbe: ExternalLocationProbe
    private let codec: SettingsTransferCodec
    private let navigationPolicy: NavigationAccessPolicy

    public init(
        invocationController: InvocationController,
        bookmarkStore: BookmarkStore,
        favoriteGroupStore: FavoriteGroupStore,
        bookmarkService: SecurityScopedBookmarkService = SecurityScopedBookmarkService(),
        locationProbe: ExternalLocationProbe = .live,
        codec: SettingsTransferCodec = SettingsTransferCodec(),
        navigationPolicy: NavigationAccessPolicy = NavigationAccessPolicy(
            homeRoot: FileManager.default.homeDirectoryForCurrentUser
        )
    ) {
        self.invocationController = invocationController
        self.bookmarkStore = bookmarkStore
        self.favoriteGroupStore = favoriteGroupStore
        self.bookmarkService = bookmarkService
        self.locationProbe = locationProbe
        self.codec = codec
        self.navigationPolicy = navigationPolicy
    }

    public func exportData(producerVersion: String) throws -> Data {
        let manifest = try codec.makeManifest(
            settings: invocationController.settings,
            favoriteGroups: favoriteGroupStore.loadFavoriteGroups(),
            savedLocations: bookmarkStore.loadSavedLocations(),
            producerVersion: producerVersion
        )
        return try codec.encode(manifest)
    }

    public func preview(
        _ data: Data
    ) -> Result<SettingsTransferImportResult, SettingsTransferCoordinatorError> {
        let manifest: SettingsTransferManifest
        do {
            manifest = try codec.decode(data)
        } catch let error as SettingsTransferError {
            return .failure(.transfer(error))
        } catch {
            return .failure(.store(String(describing: error)))
        }
        if let defaultPath = manifest.settings.defaultLocationPath {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: defaultPath, isDirectory: &isDirectory) {
                do {
                    guard isDirectory.boolValue else {
                        return .failure(.transfer(.invalidPath(defaultPath)))
                    }
                    try navigationPolicy.validateSavedLocation(
                        URL(fileURLWithPath: defaultPath, isDirectory: true)
                    )
                } catch {
                    return .failure(.transfer(.invalidPath(defaultPath)))
                }
            }
        }
        let importedLocations = manifest.savedLocations.map(resolveImportedLocation)
        return .success(
            SettingsTransferImportResult(
                settings: manifest.settings.appSettings,
                favoriteGroups: manifest.favoriteGroups,
                savedLocations: importedLocations,
                unresolvedLocationCount: importedLocations.filter {
                    ExternalLocationStateResolver.isUsable($0.availability) == false
                }.count
            )
        )
    }

    public func replace(with data: Data) -> Result<SettingsTransferImportResult, SettingsTransferCoordinatorError> {
        let imported: SettingsTransferImportResult
        switch preview(data) {
        case .success(let preview):
            imported = preview
        case .failure(let error):
            return .failure(error)
        }

        let previousGroups: [FavoriteGroup]
        let previousLocations: [SavedLocation]
        do {
            previousGroups = try favoriteGroupStore.loadFavoriteGroups()
            previousLocations = try bookmarkStore.loadSavedLocations()
        } catch {
            return .failure(.store(String(describing: error)))
        }

        let transaction = invocationController.commitImportedSettings(
            imported.settings,
            persistAdditionalStores: {
                try self.favoriteGroupStore.saveFavoriteGroups(imported.favoriteGroups)
                try self.bookmarkStore.saveSavedLocations(imported.savedLocations)
            },
            rollbackAdditionalStores: {
                var failures: [String] = []
                do {
                    try self.bookmarkStore.saveSavedLocations(previousLocations)
                } catch {
                    failures.append("Favorites: \(error)")
                }
                do {
                    try self.favoriteGroupStore.saveFavoriteGroups(previousGroups)
                } catch {
                    failures.append("Favorite groups: \(error)")
                }
                if failures.isEmpty == false {
                    throw StoreRollbackError(failures: failures)
                }
            }
        )

        switch transaction {
        case .success:
            return .success(imported)
        case .failure(let error):
            return .failure(.transaction(error))
        }
    }

    private func resolveImportedLocation(_ transfer: TransferSavedLocation) -> SavedLocation {
        let rawResolution = bookmarkService.resolve(transfer.bookmark)
        defer {
            rawResolution.scopedURL?.close()
        }
        let resolution = policyValidatedResolution(rawResolution, transfer: transfer)
        let metadata = resolution.scopedURL.map {
            locationProbe.metadata(for: $0.url)
        }
        let availability = ExternalLocationStateResolver.availability(
            current: .unavailable,
            resolution: resolution,
            metadata: metadata,
            lastKnownExternalKind: transfer.lastKnownExternalKind,
            markRecovered: false
        )
        return transfer.savedLocation(availability: availability)
    }

    private func policyValidatedResolution(
        _ resolution: BookmarkResolution,
        transfer: TransferSavedLocation
    ) -> BookmarkResolution {
        guard let scopedURL = resolution.scopedURL else {
            return resolution
        }
        do {
            try navigationPolicy.validateResolvedBookmarkURL(
                scopedURL.url,
                declaredPath: transfer.bookmark.originalPath
            )
            return resolution
        } catch {
            return BookmarkResolution(
                scopedURL: nil,
                originalPath: transfer.bookmark.originalPath,
                isStale: false,
                availability: .permissionDenied,
                error: .permissionDenied(originalPath: transfer.bookmark.originalPath)
            )
        }
    }
}
