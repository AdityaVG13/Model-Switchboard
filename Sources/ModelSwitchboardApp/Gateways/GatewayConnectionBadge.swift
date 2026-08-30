import SwiftUI
import ModelSwitchboardCore

/// Shared SSH / direct connection copy so the dashboard section, Settings,
/// and Remote Hosts never drift into different dialects.
enum GatewayConnectionBadge {
    /// Connection state only. Update progress lives on `updateActionTitle`.
    @MainActor
    static func statusText(for runtime: GatewayRuntime) -> String {
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
    static func updateActionTitle(for runtime: GatewayRuntime, agentStale: Bool = false) -> String {
        switch runtime.forceUpdatePhase {
        case .updating:
            return "Updating…"
        case .failed:
            return "Retry"
        case .idle:
            return agentStale ? "Update agent" : "Update"
        }
    }

    @MainActor
    static func updateActionColor(
        for runtime: GatewayRuntime,
        agentStale: Bool = false,
        theme: DashboardTheme,
        accent: Color
    ) -> Color {
        switch runtime.forceUpdatePhase {
        case .updating:
            return accent
        case .failed:
            return DashboardTheme.stopRed
        case .idle:
            return agentStale ? DashboardTheme.pendingOrange : theme.faint
        }
    }

    @MainActor
    static func help(
        for runtime: GatewayRuntime,
        agentStale: Bool = false,
        remoteVersion: String? = nil
    ) -> String {
        switch runtime.forceUpdatePhase {
        case .updating(let step):
            return step
        case .failed(let message):
            return message
        case .idle:
            break
        }
        if agentStale {
            let remote = (remoteVersion?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? "unknown"
            if GatewayHub.agentDeployTarget(for: runtime.config) != nil {
                return "Host agent \(remote) is behind this app (\(RemoteAgentVersion.bundled)). Click Update to push the bundled agent over SSH and refresh models."
            }
            return "Host agent \(remote) is behind this app (\(RemoteAgentVersion.bundled)). Add an SSH user/host in Settings, then click Update."
        }
        if GatewayHub.agentDeployTarget(for: runtime.config) != nil {
            return "Update: push the agent bundled in this app over SSH, reconnect if needed, and refresh models and ports."
        }
        return "Add an SSH user/host in Settings for this gateway, then click Update to push a fresh agent."
    }
}

/// Status chip plus a separate Update button so DIRECT/SSH is not the action.
struct GatewayForceUpdateControls: View {
    @Bindable var runtime: GatewayRuntime
    var agentStale: Bool = false
    var remoteVersion: String? = nil
    let theme: DashboardTheme
    let accent: Color
    var capsuleUpdate: Bool = false
    var onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(GatewayConnectionBadge.statusText(for: runtime))
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.faint)
                .accessibilityLabel(GatewayConnectionBadge.statusText(for: runtime))

            Button(action: onUpdate) {
                Text(GatewayConnectionBadge.updateActionTitle(for: runtime, agentStale: agentStale))
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(
                        GatewayConnectionBadge.updateActionColor(
                            for: runtime,
                            agentStale: agentStale,
                            theme: theme,
                            accent: accent
                        )
                    )
                    .padding(.horizontal, capsuleUpdate ? 6 : 0)
                    .padding(.vertical, capsuleUpdate ? 3 : 0)
                    .background {
                        if capsuleUpdate {
                            Capsule().fill(theme.btnBg.opacity(0.85))
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietCraftPressStyle())
            .disabled(runtime.forceUpdatePhase.isUpdating)
            .help(GatewayConnectionBadge.help(
                for: runtime,
                agentStale: agentStale,
                remoteVersion: remoteVersion
            ))
            .accessibilityLabel("Update " + runtime.name)
            .accessibilityHint(GatewayConnectionBadge.help(
                for: runtime,
                agentStale: agentStale,
                remoteVersion: remoteVersion
            ))
        }
    }
}
