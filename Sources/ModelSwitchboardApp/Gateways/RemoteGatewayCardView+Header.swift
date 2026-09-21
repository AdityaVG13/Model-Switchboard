import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    func header(agentStale: Bool, metrics: HostMetricsPayload?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            headerDot
            headerIdentity(metrics: metrics)
            Spacer(minLength: 0)
            GatewayForceUpdateControls(
                runtime: runtime,
                agentStale: agentStale,
                remoteVersion: metrics?.agentVersion,
                theme: theme,
                accent: accent,
                capsuleUpdate: true,
                onUpdate: {
                    Task {
                        await hub.forceUpdateGateway(id: runtime.id)
                        await metricsMonitor.pollOnce()
                    }
                }
            )
        }
    }
}
