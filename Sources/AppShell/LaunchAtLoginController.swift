import Foundation
import ServiceManagement
import SettingsFeature

struct LiveLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        map(SMAppService.mainApp.status)
    }

    func apply(enabled: Bool) -> Result<LaunchAtLoginStatus, LaunchAtLoginError> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(status)
        } catch {
            return .failure(.runtimeFailed(String(describing: error)))
        }
    }

    private func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }
}
