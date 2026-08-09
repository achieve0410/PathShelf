import Foundation

public enum SettingsStatusFormatter {
    public static func describe(_ status: LaunchAtLoginStatus) -> String {
        switch status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notRegistered:
            return "Not registered"
        case .notFound:
            return "Available after PathShelf is installed in Applications."
        }
    }
}
