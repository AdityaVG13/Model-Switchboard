import Foundation
import OSLog
import ServiceManagement
import ModelSwitchboardCore

extension LaunchAtLoginManager {
    func applyLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try unregisterCompanionEditionLoginItem()
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            Self.logger.error(
                "Login item update failed: \(error.localizedDescription, privacy: .public)"
            )
            lastError =
                "Could not update Login Items. Check System Settings → General → Login Items & Extensions."
        }
    }
}
