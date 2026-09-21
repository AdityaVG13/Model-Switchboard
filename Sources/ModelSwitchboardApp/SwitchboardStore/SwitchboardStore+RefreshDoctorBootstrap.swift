import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func applyBootstrapDiagnostic(_ message: String?) {
        if let message {
            // Keep the 3s recovering cadence. Clearing it here left local
            // LaunchAgent / Tailscale DNS failures on the idle 10-minute
            // poll after the 1.5s bootstrap wait painted `.blocked`.
            isRecoveringFromTransportFailure = true
            refreshState = .blocked(message: message)
        } else if refreshState.isBlocked {
            // Clearing the sticky diagnostic leaves any transient failure intact.
            refreshState = .idle
        }
    }
}
