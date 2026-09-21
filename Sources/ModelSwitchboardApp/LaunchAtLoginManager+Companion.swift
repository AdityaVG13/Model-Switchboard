import Foundation
import OSLog
import ServiceManagement
import ModelSwitchboardCore

extension LaunchAtLoginManager {
    @available(macOS 13.0, *)
    func unregisterCompanionEditionLoginItem() throws {
        guard
            let currentBundleIdentifier = Bundle.main.bundleIdentifier,
            let companionBundleIdentifier = LoginItemBundleIdentifiers.companion(for: currentBundleIdentifier)
        else {
            return
        }

        let companionService = SMAppService.loginItem(identifier: companionBundleIdentifier)
        switch companionService.status {
        case .enabled, .requiresApproval:
            try companionService.unregister()
        case .notFound, .notRegistered:
            break
        @unknown default:
            break
        }
    }
}
