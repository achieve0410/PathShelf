import AppKit
import SettingsFeature
import UniformTypeIdentifiers

struct ConfigurationTransferProbeResult {
    var roundTripPassed: Bool
    var favoriteIncluded: Bool
    var malformedRejected: Bool
}

@MainActor
final class ConfigurationTransferController: NSObject {
    private let coordinator: SettingsTransferCoordinator
    private let producerVersion: String

    var onStatus: ((String, String?) -> Void)?
    var onImport: ((SettingsTransferImportResult) -> Void)?

    init(coordinator: SettingsTransferCoordinator, producerVersion: String) {
        self.coordinator = coordinator
        self.producerVersion = producerVersion
    }

    func runProbe(in directory: URL) -> ConfigurationTransferProbeResult {
        do {
            let fileURL = directory.appendingPathComponent(
                "PathShelf-Configuration.json",
                isDirectory: false
            )
            let data = try coordinator.exportData(producerVersion: producerVersion)
            try data.write(to: fileURL, options: .atomic)
            let persistedData = try Data(contentsOf: fileURL)
            guard case .success(let preview) = coordinator.preview(persistedData),
                  case .success = coordinator.replace(with: persistedData) else {
                return ConfigurationTransferProbeResult(
                    roundTripPassed: false,
                    favoriteIncluded: false,
                    malformedRejected: false
                )
            }
            let malformedRejected: Bool
            if case .failure(.transfer(.invalidDocument)) = coordinator.preview(
                Data("not-json".utf8)
            ) {
                malformedRejected = true
            } else {
                malformedRejected = false
            }
            return ConfigurationTransferProbeResult(
                roundTripPassed: true,
                favoriteIncluded: preview.savedLocations.isEmpty == false,
                malformedRejected: malformedRejected
            )
        } catch {
            return ConfigurationTransferProbeResult(
                roundTripPassed: false,
                favoriteIncluded: false,
                malformedRejected: false
            )
        }
    }

    @objc func exportConfiguration(_ sender: Any?) {
        guard let window = hostWindow(for: sender) else {
            onStatus?("Could not export configuration.", nil)
            return
        }
        let panel = NSSavePanel()
        panel.identifier = .init("PathShelf.Settings.ExportPanel")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PathShelf-Configuration.json"
        panel.prompt = "Export"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            guard response == .OK, let url = panel.url else {
                onStatus?("Export canceled.", nil)
                return
            }
            do {
                let data = try coordinator.exportData(producerVersion: producerVersion)
                try withSecurityScopedAccess(to: url) {
                    try data.write(to: url, options: .atomic)
                }
                onStatus?("Configuration exported: \(url.lastPathComponent).", url.path)
            } catch {
                onStatus?("Could not export configuration: The file could not be written.", url.path)
            }
        }
    }

    @objc func importConfiguration(_ sender: Any?) {
        guard let window = hostWindow(for: sender) else {
            onStatus?("Could not import configuration.", nil)
            return
        }
        let panel = NSOpenPanel()
        panel.identifier = .init("PathShelf.Settings.ImportPanel")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            guard response == .OK, let url = panel.url else {
                onStatus?("Import canceled.", nil)
                return
            }
            let data: Data
            do {
                data = try withSecurityScopedAccess(to: url) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }
            } catch {
                onStatus?(
                    "Could not import configuration: The file could not be read. Existing data was kept.",
                    url.path
                )
                return
            }
            switch coordinator.preview(data) {
            case .success(let preview):
                confirmImport(data: data, preview: preview, sourceURL: url, window: window)
            case .failure(let error):
                onStatus?(importFailureMessage(error), url.path)
            }
        }
    }

    private func confirmImport(
        data: Data,
        preview: SettingsTransferImportResult,
        sourceURL: URL,
        window: NSWindow
    ) {
        let alert = NSAlert()
        alert.window.identifier = .init("PathShelf.Settings.ImportConfirmation")
        alert.messageText = "Import Configuration?"
        alert.informativeText = confirmationMessage(preview)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            guard response == .alertFirstButtonReturn else {
                onStatus?("Import canceled.", sourceURL.path)
                return
            }
            switch coordinator.replace(with: data) {
            case .success(let result):
                onImport?(result)
                if result.unresolvedLocationCount > 0 {
                    onStatus?(
                        "Configuration imported. \(result.unresolvedLocationCount) Favorite(s) need folder access.",
                        sourceURL.path
                    )
                } else {
                    onStatus?("Configuration imported.", sourceURL.path)
                }
            case .failure(let error):
                onStatus?(importFailureMessage(error), sourceURL.path)
            }
        }
    }

    private func confirmationMessage(_ preview: SettingsTransferImportResult) -> String {
        var message = """
        Replace current settings, \(preview.favoriteGroups.count) Favorite group(s), \
        and \(preview.savedLocations.count) Favorite(s)?
        """
        if preview.unresolvedLocationCount > 0 {
            message += """


            \(preview.unresolvedLocationCount) Favorite(s) need folder access on this Mac. \
            Use Choose New Folder… after import.
            """
        }
        if let path = preview.settings.defaultLocationPath,
           FileManager.default.fileExists(atPath: path) == false {
            message += """


            The default location is unavailable on this Mac. Home directory will be used \
            when the panel opens.
            """
        }
        return message
    }

    private func importFailureMessage(_ error: SettingsTransferCoordinatorError) -> String {
        switch error {
        case .transfer(.unsupportedVersion):
            return "Could not import configuration: This configuration version is not supported."
        case .transfer:
            return "Could not import configuration: The selected file is invalid."
        case .store:
            return "Could not import configuration. Existing settings and Favorites were kept."
        case .transaction(let error):
            return "Could not import configuration. Existing settings and Favorites were kept. \(error.description)"
        }
    }

    private func hostWindow(for sender: Any?) -> NSWindow? {
        (sender as? NSView)?.window ?? NSApp.keyWindow
    }

    private func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
