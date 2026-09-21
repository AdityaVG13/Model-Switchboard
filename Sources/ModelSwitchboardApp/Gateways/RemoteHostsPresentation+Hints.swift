import SwiftUI
import ModelSwitchboardCore

extension RemoteHostsPresentation {
    static func agentUpgradeHint(for runtime: GatewayRuntime) -> String {
        switch runtime.config.connection {
        case .ssh:
            return "Click Update to push a fresh agent from this Mac (or use Settings → Install Agent / the one-liner below). Until then only process RSS is shown, not GPU VRAM."
        case .direct:
            return "Click Update to push a fresh agent over SSH to this Tailscale host. Login uses your Mac username unless you SSH as a different user. Or paste the one-liner below on the box."
        }
    }

    static func tailnetDotColor(metrics: HostMetricsPayload?) -> Color {
        if metrics?.tailscale?.online == false { return DashboardTheme.stopRed }
        if !(metrics?.tailscale?.health ?? []).isEmpty { return DashboardTheme.pendingOrange }
        return DashboardTheme.runningGreen
    }
}
