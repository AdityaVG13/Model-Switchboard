import Foundation
import OSLog
import ServiceManagement
import ModelSwitchboardCore

extension LaunchAtLoginManager {
    func applyLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                // Best-effort: legacy cleanup must never block enabling
                // this app's own login item.
                do {
                    try unregisterLegacyPlusLoginItem()
                } catch {
                    Self.logger.error(
                        "Legacy Plus login item cleanup failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
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
