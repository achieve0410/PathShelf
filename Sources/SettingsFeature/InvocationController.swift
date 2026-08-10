import Foundation
import PanelFeature

public protocol HotKeyRegistering: Sendable {
    var activeBinding: ShortcutBinding? { get }
    func registerInitial(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError>
    func validateAndCommit(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError>
    func unregister()
}

public enum LaunchAtLoginStatus: String, Codable, Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
}

public protocol LaunchAtLoginManaging: Sendable {
    var status: LaunchAtLoginStatus { get }
    func apply(enabled: Bool) -> Result<LaunchAtLoginStatus, LaunchAtLoginError>
}

public enum LaunchAtLoginError: Error, Equatable, CustomStringConvertible, Sendable {
    case runtimeFailed(String)

    public var description: String {
        switch self {
        case .runtimeFailed(let message):
            return "Launch-at-login runtime update failed: \(message)"
        }
    }
}

public enum InvocationControllerError: Error, Equatable, CustomStringConvertible {
    case hotKey(HotKeyRegistrationError)
    case launchAtLogin(LaunchAtLoginError)
    case persistenceFailed(String)
    case launchAtLoginPersistenceFailed(String)
    case launchAtLoginPersistenceAndRollbackFailed(persistence: String, rollback: LaunchAtLoginError)
    case persistenceAndRollbackFailed(persistence: String, rollback: HotKeyRegistrationError)

    public var description: String {
        switch self {
        case .hotKey(let error):
            return error.description
        case .launchAtLogin(let error):
            return error.description
        case .persistenceFailed(let message):
            return "Settings could not be saved after shortcut registration: \(message)"
        case .launchAtLoginPersistenceFailed(let message):
            return "Settings could not be saved after launch-at-login update: \(message)"
        case .launchAtLoginPersistenceAndRollbackFailed(let persistence, let rollback):
            return "Settings could not be saved after launch-at-login update: \(persistence). Rollback also failed: \(rollback.description)."
        case .persistenceAndRollbackFailed(let persistence, let rollback):
            return "Settings could not be saved after shortcut registration: \(persistence). Rollback also failed: \(rollback.description). Runtime shortcut was unregistered."
        }
    }
}

public enum ImportedSettingsCommitError: Error, Equatable, CustomStringConvertible, Sendable {
    case hotKey(HotKeyRegistrationError)
    case launchAtLogin(LaunchAtLoginError)
    case contradictoryLaunchAtLoginStatus(requestedEnabled: Bool, actual: LaunchAtLoginStatus)
    case persistence(String)
    case rollbackFailed(primary: String, failures: [String])

    public var description: String {
        switch self {
        case .hotKey(let error):
            return error.description
        case .launchAtLogin(let error):
            return error.description
        case .contradictoryLaunchAtLoginStatus(let requestedEnabled, let actual):
            return "Launch-at-login requested \(requestedEnabled), got \(actual.rawValue)."
        case .persistence(let message):
            return message
        case .rollbackFailed(let primary, let failures):
            return "\(primary) Rollback failed: \(failures.joined(separator: "; "))."
        }
    }
}

public final class InvocationController: @unchecked Sendable {
    private let settingsStore: SettingsPersisting
    private let hotKeyController: HotKeyRegistering
    private let launchAtLoginController: LaunchAtLoginManaging

    public private(set) var settings: AppSettings
    public private(set) var lastError: InvocationControllerError?

    public init(
        settingsStore: SettingsPersisting,
        hotKeyController: HotKeyRegistering,
        launchAtLoginController: LaunchAtLoginManaging = NoopLaunchAtLoginManager()
    ) {
        self.settingsStore = settingsStore
        self.hotKeyController = hotKeyController
        self.launchAtLoginController = launchAtLoginController
        self.settings = .default
    }

    public var activeShortcut: ShortcutBinding? {
        hotKeyController.activeBinding
    }

    public func loadAndRegister() {
        settings = loadSettings()
        registerLoadedShortcut()
    }

    public func commitImportedSettings(
        _ candidate: AppSettings,
        persistAdditionalStores: () throws -> Void,
        rollbackAdditionalStores: () throws -> Void
    ) -> Result<Void, ImportedSettingsCommitError> {
        let previous = settings
        let previousBinding = hotKeyController.activeBinding
        let previousLaunchStatus = launchAtLoginController.status
        let shortcutChanged = previousBinding != candidate.shortcut
        var launchChanged = false

        func rollbackRuntime(primary: ImportedSettingsCommitError) -> ImportedSettingsCommitError {
            var failures: [String] = []

            if launchChanged {
                let previousLaunchEnabled = previousLaunchStatus == .enabled
                    || previousLaunchStatus == .requiresApproval
                switch launchAtLoginController.apply(enabled: previousLaunchEnabled) {
                case .success(let status):
                    let acceptedNotFound = previousLaunchEnabled == false && status == .notFound
                    if Self.isSuccessfulLaunchStatus(
                        status,
                        requestedEnabled: previousLaunchEnabled
                    ) == false && acceptedNotFound == false {
                        failures.append("Launch-at-login rollback returned \(status.rawValue)")
                    }
                case .failure(let error):
                    failures.append("Launch-at-login rollback: \(error.description)")
                }
            }

            if shortcutChanged {
                if let previousBinding {
                    switch hotKeyController.validateAndCommit(previousBinding) {
                    case .success:
                        break
                    case .failure(let error):
                        hotKeyController.unregister()
                        failures.append("Shortcut rollback: \(error.description)")
                    }
                } else {
                    hotKeyController.unregister()
                }
            }

            settings = previous
            if failures.isEmpty {
                return primary
            }
            return .rollbackFailed(primary: primary.description, failures: failures)
        }

        if shortcutChanged {
            switch hotKeyController.validateAndCommit(candidate.shortcut) {
            case .success:
                break
            case .failure(let error):
                settings = previous
                return .failure(.hotKey(error))
            }
        }

        let launchStatus = previousLaunchStatus
        let acceptedNotFound = candidate.launchAtLogin == false && launchStatus == .notFound
        if Self.isSuccessfulLaunchStatus(
            launchStatus,
            requestedEnabled: candidate.launchAtLogin
        ) == false && acceptedNotFound == false {
            if candidate.launchAtLogin && launchStatus == .notFound {
                return .failure(
                    rollbackRuntime(
                        primary: .contradictoryLaunchAtLoginStatus(
                            requestedEnabled: true,
                            actual: .notFound
                        )
                    )
                )
            }
            switch launchAtLoginController.apply(enabled: candidate.launchAtLogin) {
            case .success(let status):
                launchChanged = true
                guard Self.isSuccessfulLaunchStatus(
                    status,
                    requestedEnabled: candidate.launchAtLogin
                ) else {
                    return .failure(
                        rollbackRuntime(
                            primary: .contradictoryLaunchAtLoginStatus(
                                requestedEnabled: candidate.launchAtLogin,
                                actual: status
                            )
                        )
                    )
                }
            case .failure(let error):
                return .failure(rollbackRuntime(primary: .launchAtLogin(error)))
            }
        }

        do {
            try persistAdditionalStores()
            try settingsStore.save(candidate)
            settings = candidate
            lastError = nil
            return .success(())
        } catch {
            let primary = ImportedSettingsCommitError.persistence(String(describing: error))
            var rollbackFailures: [String] = []
            do {
                try rollbackAdditionalStores()
            } catch {
                rollbackFailures.append("Additional stores: \(error)")
            }
            let runtimeResult = rollbackRuntime(primary: primary)
            if case .rollbackFailed(_, let failures) = runtimeResult {
                rollbackFailures.append(contentsOf: failures)
            }
            if rollbackFailures.isEmpty {
                return .failure(primary)
            }
            return .failure(
                .rollbackFailed(
                    primary: primary.description,
                    failures: rollbackFailures
                )
            )
        }
    }

    public func validateAndCommitShortcut(_ binding: ShortcutBinding) -> Result<Void, InvocationControllerError> {
        let previous = settings
        switch hotKeyController.validateAndCommit(binding) {
        case .success:
            var candidate = previous
            candidate.shortcut = binding
            do {
                try settingsStore.save(candidate)
                settings = candidate
                lastError = nil
                return .success(())
            } catch {
                let persistenceMessage = String(describing: error)
                switch hotKeyController.validateAndCommit(previous.shortcut) {
                case .success:
                    settings = previous
                    let mapped = InvocationControllerError.persistenceFailed(persistenceMessage)
                    lastError = mapped
                    return .failure(mapped)
                case .failure(let rollbackError):
                    hotKeyController.unregister()
                    settings = previous
                    let mapped = InvocationControllerError.persistenceAndRollbackFailed(
                        persistence: persistenceMessage,
                        rollback: rollbackError
                    )
                    lastError = mapped
                    return .failure(mapped)
                }
            }
        case .failure(let error):
            settings = previous
            let mapped = InvocationControllerError.hotKey(error)
            lastError = mapped
            return .failure(mapped)
        }
    }

    public func updatePanelPlacement(_ placement: PanelPlacementPreference) -> Result<Void, InvocationControllerError> {
        var candidate = settings
        candidate.panelPlacement = placement
        do {
            try settingsStore.save(candidate)
            settings = candidate
            lastError = nil
            return .success(())
        } catch {
            let mapped = InvocationControllerError.persistenceFailed(String(describing: error))
            lastError = mapped
            return .failure(mapped)
        }
    }

    public func updateBrowserPreferences(
        showHiddenFiles: Bool,
        visibleDetailColumns: [FileDetailColumn],
        defaultLocationPath: String?
    ) -> Result<Void, InvocationControllerError> {
        var candidate = settings
        candidate.showHiddenFiles = showHiddenFiles
        candidate.visibleDetailColumns = visibleDetailColumns
        candidate.defaultLocationPath = defaultLocationPath
        do {
            try settingsStore.save(candidate)
            settings = candidate
            lastError = nil
            return .success(())
        } catch {
            let mapped = InvocationControllerError.persistenceFailed(String(describing: error))
            lastError = mapped
            return .failure(mapped)
        }
    }

    public var launchAtLoginStatus: LaunchAtLoginStatus {
        launchAtLoginController.status
    }

    public func updateLaunchAtLogin(enabled: Bool) -> Result<LaunchAtLoginStatus, InvocationControllerError> {
        let previous = settings
        let currentStatus = launchAtLoginController.status
        if Self.isSuccessfulLaunchStatus(currentStatus, requestedEnabled: enabled) {
            guard previous.launchAtLogin != enabled else {
                return .success(currentStatus)
            }
            var candidate = previous
            candidate.launchAtLogin = enabled
            do {
                try settingsStore.save(candidate)
                settings = candidate
                lastError = nil
                return .success(currentStatus)
            } catch {
                let mapped = InvocationControllerError.launchAtLoginPersistenceFailed(
                    String(describing: error)
                )
                lastError = mapped
                return .failure(mapped)
            }
        }
        switch launchAtLoginController.apply(enabled: enabled) {
        case .success(let newStatus) where Self.isSuccessfulLaunchStatus(newStatus, requestedEnabled: enabled):
            guard previous.launchAtLogin != enabled else {
                lastError = nil
                return .success(newStatus)
            }
            var candidate = previous
            candidate.launchAtLogin = enabled
            do {
                try settingsStore.save(candidate)
                settings = candidate
                lastError = nil
                return .success(newStatus)
            } catch {
                let persistenceMessage = String(describing: error)
                switch launchAtLoginController.apply(enabled: previous.launchAtLogin) {
                case .success:
                    settings = previous
                    let mapped = InvocationControllerError.launchAtLoginPersistenceFailed(persistenceMessage)
                    lastError = mapped
                    return .failure(mapped)
                case .failure(let rollbackError):
                    settings = previous
                    let mapped = InvocationControllerError.launchAtLoginPersistenceAndRollbackFailed(
                        persistence: persistenceMessage,
                        rollback: rollbackError
                    )
                    lastError = mapped
                    return .failure(mapped)
                }
            }
        case .success(let contradictoryStatus):
            settings = previous
            let mapped = InvocationControllerError.launchAtLogin(
                .runtimeFailed("Contradictory launch-at-login status: requested \(enabled), got \(contradictoryStatus.rawValue)")
            )
            lastError = mapped
            return .failure(mapped)
        case .failure(let error):
            settings = previous
            let mapped = InvocationControllerError.launchAtLogin(error)
            lastError = mapped
            return .failure(mapped)
        }
    }

    private func loadSettings() -> AppSettings {
        do {
            return try settingsStore.load()
        } catch SettingsStoreError.missingFile {
            try? settingsStore.save(.default)
            return .default
        } catch {
            return .default
        }
    }

    private func registerLoadedShortcut() {
        switch hotKeyController.registerInitial(settings.shortcut) {
        case .success:
            lastError = nil
        case .failure(let error):
            lastError = .hotKey(error)
        }
    }

    private static func isSuccessfulLaunchStatus(_ status: LaunchAtLoginStatus, requestedEnabled: Bool) -> Bool {
        if requestedEnabled {
            return status == .enabled || status == .requiresApproval
        }
        return status == .notRegistered
    }
}

public struct NoopLaunchAtLoginManager: LaunchAtLoginManaging {
    public var status: LaunchAtLoginStatus { .notRegistered }

    public init() {}

    public func apply(enabled: Bool) -> Result<LaunchAtLoginStatus, LaunchAtLoginError> {
        .success(enabled ? .requiresApproval : .notRegistered)
    }
}
