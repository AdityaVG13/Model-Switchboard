import SwiftUI
import ModelSwitchboardCore

extension GatewayConnectionBadge {
    /// Connection state only. Update progress lives on `updateActionTitle`.
    @MainActor
    static func statusText(for runtime: GatewayRuntime) -> String {
        switch runtime.config.kind {
        case .direct:
            return directStatusText(for: runtime)
        case .ssh:
            return sshStatusText(for: runtime)
        }
    }

    @MainActor
    static func directStatusText(for runtime: GatewayRuntime) -> String {
        runtime.store.lastError != nil ? "DIRECT · ERROR" : "DIRECT"
    }

    @MainActor
    static func sshStatusText(for runtime: GatewayRuntime) -> String {
        switch runtime.tunnelState {
        case .idle: return "SSH · OFF"
        case .connecting: return "SSH · CONNECTING"
        case .established:
            return runtime.store.lastError != nil ? "SSH · ERROR" : "SSH · TUNNELED"
        case .failed: return "SSH · FAILED"
        }
    }
}
