import Foundation
import ServiceManagement
import ModelSwitchboardCore

extension LaunchAtLoginManager {
    @available(macOS 13.0, *)
    static func flags(from status: SMAppService.Status) -> (enabled: Bool, requiresApproval: Bool) {
        switch status {
        case .enabled:
            return (true, false)
        case .requiresApproval:
            return (false, true)
        case .notFound, .notRegistered:
            return (false, false)
        @unknown default:
            return (false, false)
        }
    }
}
