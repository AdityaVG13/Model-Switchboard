import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func remoteGatewaySection(for runtime: GatewayRuntime) -> some View {
        RemoteGatewaySectionView(
            runtime: runtime,
            filter: profileFilter,
            excludeProfileIDs: remoteHeroProfileIDsByGateway[runtime.id] ?? [],
            hostMetrics: hostMetricsMonitor.entry(forGatewayID: runtime.id).metrics,
            agentStale: {
                let entry = hostMetricsMonitor.entry(forGatewayID: runtime.id)
                return RemoteAgentVersion.isRemoteStale(
                    metrics: entry.metrics,
                    unsupported: entry.unsupported
                )
            }(),
            onForceUpdate: {
                Task {
                    await hub.forceUpdateGateway(id: runtime.id)
                    await hostMetricsMonitor.pollOnce()
                }
            },
            theme: theme,
            accent: accent,
            onOpenBenchmarks: { setInspectorPanel(.benchmarks) }
        )
    }
}
