import SwiftUI

/// Shared SSH / direct connection badge copy so the dashboard section and
/// Remote Hosts panel never drift into different dialects.
enum GatewayConnectionBadge {
    @MainActor
    static func text(for runtime: GatewayRuntime) -> String {
        switch runtime.forceUpdatePhase {
        case .updating:
            return "UPDATING…"
        case .failed:
            return "UPDATE FAILED"
        case .idle:
            break
        }

        switch runtime.config.kind {
        case .direct:
            if runtime.store.lastError != nil {
                return "DIRECT · ERROR"
            }
            return "DIRECT"
        case .ssh:
            switch runtime.tunnelState {
            case .idle: return "SSH · OFF"
            case .connecting: return "SSH · CONNECTING"
            case .established:
                if runtime.store.lastError != nil {
                    return "SSH · ERROR"
                }
                return "SSH · TUNNELED"
            case .failed: return "SSH · FAILED"
            }
        }
    }

    @MainActor
    static func help(for runtime: GatewayRuntime) -> String {
        switch runtime.forceUpdatePhase {
        case .updating(let step):
            return step
        case .failed(let message):
            return message
        case .idle:
            break
        }
        if GatewayHub.agentDeployConfig(for: runtime.config) != nil {
            return "Force update: push the bundled agent over SSH, reconnect if needed, and hard-refresh models and ports."
        }
        return "Add an SSH user/host in Settings for this gateway, then click again to push a fresh agent."
    }
}
