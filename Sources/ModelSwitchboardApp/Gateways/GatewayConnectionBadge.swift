import SwiftUI

/// Shared SSH / direct connection badge copy so the dashboard section and
/// Remote Hosts panel never drift into different dialects.
enum GatewayConnectionBadge {
    @MainActor
    static func text(for runtime: GatewayRuntime) -> String {
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
}
