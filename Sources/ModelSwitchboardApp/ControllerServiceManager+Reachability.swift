import Darwin
import Foundation
import ModelSwitchboardCore
import ServiceManagement

extension ControllerServiceManager {
    func unreachableDiagnostic(for status: SMAppService.Status) -> String {
        switch status {
        case .requiresApproval:
            return "Enable Model Switchboard in System Settings → General → Login Items & Extensions so the local controller can start."
        case .notFound:
            return "Controller LaunchAgent was not found in this app bundle. Reinstall Model Switchboard so the embedded controller can register."
        case .enabled, .notRegistered:
            return "Could not start the local controller on port \(ControllerEndpointDefaults.port). Try Quit and reopen, or reinstall."
        @unknown default:
            return "Could not start the local controller on port \(ControllerEndpointDefaults.port). Try Quit and reopen, or reinstall."
        }
    }
}
