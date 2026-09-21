import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func remoteActiveCard(_ summary: RemoteHeroSummary) -> some View {
        let runtime = hub.enabledRemoteRuntimes.first { $0.id == summary.gatewayID }
        let remoteStore = runtime?.store ?? store
        let hostMetrics = runtime.map { hostMetricsMonitor.entry(forGatewayID: $0.id).metrics } ?? nil
        return ActiveProfileHeroView(
            profile: summary.profile,
            store: remoteStore,
            context: .remote(gatewayName: summary.name),
            hostMetrics: hostMetrics,
            decodeTokensPerSecond: decodeTokensPerSecond(for: summary.profile.profile, in: remoteStore),
            ttftMilliseconds: ttftMilliseconds(for: summary.profile.profile, in: remoteStore),
            reachableEndpointURL: runtime?.reachableEndpointURL(for: summary.profile),
            onOpenBenchmarks: { setInspectorPanel(.benchmarks) },
            theme: theme,
            accent: accent
        )
    }
}
