import Foundation
import PanelFeature

public enum FileDetailColumn: String, Codable, CaseIterable, Sendable {
    case modified
    case kind
    case size
    case created
    case availability
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var panelPlacement: PanelPlacementPreference
    public var shortcut: ShortcutBinding
    public var launchAtLogin: Bool
    public var showHiddenFiles: Bool
    public var visibleDetailColumns: [FileDetailColumn]
    public var defaultLocationPath: String?

    public init(
        panelPlacement: PanelPlacementPreference = PanelPlacementPreference(),
        shortcut: ShortcutBinding = .default,
        launchAtLogin: Bool = false,
        showHiddenFiles: Bool = false,
        visibleDetailColumns: [FileDetailColumn] = [.modified],
        defaultLocationPath: String? = nil
    ) {
        self.panelPlacement = panelPlacement
        self.shortcut = shortcut
        self.launchAtLogin = launchAtLogin
        self.showHiddenFiles = showHiddenFiles
        self.visibleDetailColumns = visibleDetailColumns
        self.defaultLocationPath = defaultLocationPath
    }

    public static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case panelPlacement
        case shortcut
        case launchAtLogin
        case showHiddenFiles
        case visibleDetailColumns
        case defaultLocationPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.panelPlacement = try container.decodeIfPresent(
            PanelPlacementPreference.self,
            forKey: .panelPlacement
        ) ?? PanelPlacementPreference()
        self.shortcut = try container.decodeIfPresent(
            ShortcutBinding.self,
            forKey: .shortcut
        ) ?? .default
        self.launchAtLogin = try container.decodeIfPresent(
            Bool.self,
            forKey: .launchAtLogin
        ) ?? false
        self.showHiddenFiles = try container.decodeIfPresent(
            Bool.self,
            forKey: .showHiddenFiles
        ) ?? false
        self.visibleDetailColumns = try container.decodeIfPresent(
            [FileDetailColumn].self,
            forKey: .visibleDetailColumns
        ) ?? [.modified]
        self.defaultLocationPath = try container.decodeIfPresent(
            String.self,
            forKey: .defaultLocationPath
        )
    }
}
