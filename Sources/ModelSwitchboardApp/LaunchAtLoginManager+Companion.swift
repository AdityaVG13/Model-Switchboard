import Foundation
import OSLog
import ServiceManagement
import ModelSwitchboardCore

extension LaunchAtLoginManager {
    /// One-way legacy cleanup: a Plus-edition login item must not survive
    /// alongside the unified app (two menu bar icons, two controllers).
    @available(macOS 13.0, *)
    func unregisterLegacyPlusLoginItem() throws {
        let legacyService = SMAppService.loginItem(identifier: "io.modelswitchboard.plus")
        switch legacyService.status {
        case .enabled, .requiresApproval:
            try legacyService.unregister()
        case .notFound, .notRegistered:
            break
        @unknown default:
            break
        }
    }
}
