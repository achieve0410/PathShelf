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

    public init(
        invocationController: InvocationController,
        bookmarkStore: BookmarkStore,
        favoriteGroupStore: FavoriteGroupStore,
        bookmarkService: SecurityScopedBookmarkService = SecurityScopedBookmarkService(),
        locationProbe: ExternalLocationProbe = .live,
        codec: SettingsTransferCodec = SettingsTransferCodec()
    ) {
        self.invocationController = invocationController
        self.bookmarkStore = bookmarkStore
        self.favoriteGroupStore = favoriteGroupStore
        self.bookmarkService = bookmarkService
        self.locationProbe = locationProbe
        self.codec = codec
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

    public func replace(with data: Data) -> Result<SettingsTransferImportResult, SettingsTransferCoordinatorError> {
        let manifest: SettingsTransferManifest
        do {
            manifest = try codec.decode(data)
        } catch let error as SettingsTransferError {
            return .failure(.transfer(error))
        } catch {
            return .failure(.store(String(describing: error)))
        }

        let previousGroups: [FavoriteGroup]
        let previousLocations: [SavedLocation]
        do {
            previousGroups = try favoriteGroupStore.loadFavoriteGroups()
            previousLocations = try bookmarkStore.loadSavedLocations()
        } catch {
            return .failure(.store(String(describing: error)))
        }

        let importedLocations = manifest.savedLocations.map(resolveImportedLocation)
        let transaction = invocationController.commitImportedSettings(
            manifest.settings.appSettings,
            persistAdditionalStores: {
                try self.favoriteGroupStore.saveFavoriteGroups(manifest.favoriteGroups)
                try self.bookmarkStore.saveSavedLocations(importedLocations)
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
        case .failure(let error):
            return .failure(.transaction(error))
        }
    }

    private func resolveImportedLocation(_ transfer: TransferSavedLocation) -> SavedLocation {
        let resolution = bookmarkService.resolve(transfer.bookmark)
        defer {
            resolution.scopedURL?.close()
        }
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
}
