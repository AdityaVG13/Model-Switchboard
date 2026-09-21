import SwiftUI
import ModelSwitchboardCore

extension GatewayConnectionBadge {
    @MainActor
    static func idleHelp(
        for runtime: GatewayRuntime,
        agentStale: Bool,
        remoteVersion: String?
    ) -> String {
        if agentStale {
            return staleAgentHelp(for: runtime, remote: remoteVersion.nonEmptyTrimmed ?? "unknown")
        }
        return updateIdleHelp(for: runtime)
    }

    @MainActor
    static func staleAgentHelp(for runtime: GatewayRuntime, remote: String) -> String {
        if GatewayHub.agentDeployTarget(for: runtime.config) != nil {
            return "Host agent \(remote) is behind this app (\(RemoteAgentVersion.bundled)). Click Update to push the bundled agent over SSH and refresh models."
        }
        return "Host agent \(remote) is behind this app (\(RemoteAgentVersion.bundled)). Add an SSH user/host in Settings, then click Update."
    }

    @MainActor
    static func updateIdleHelp(for runtime: GatewayRuntime) -> String {
        if GatewayHub.agentDeployTarget(for: runtime.config) != nil {
            return "Update: push the agent bundled in this app over SSH, reconnect if needed, and refresh models and ports."
        }
        return "Add an SSH user/host in Settings for this gateway, then click Update to push a fresh agent."
    }
}
