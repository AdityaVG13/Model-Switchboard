import SwiftUI
import ModelSwitchboardCore

extension GatewayConnectionBadge {
    @MainActor
    static func help(
        for runtime: GatewayRuntime,
        agentStale: Bool = false,
        remoteVersion: String? = nil
    ) -> String {
        if let step = runtime.forceUpdatePhase.updatingStep {
            return step
        }
        if let message = runtime.forceUpdatePhase.failureMessage {
            return message
        }
        return idleHelp(for: runtime, agentStale: agentStale, remoteVersion: remoteVersion)
    }
}
