import Foundation
import Observation
import SwiftUI
import ModelSwitchboardCore

/// One gateway's live state: its store, and for SSH gateways the tunnel.
@MainActor
@Observable
final class GatewayRuntime: Identifiable {
    nonisolated let id: String
    private(set) var config: GatewayConfig
    let store: SwitchboardStore
    let tunnel: SSHTunnelManager?
    var tunnelState: SSHTunnelManager.State = .idle
    /// Remote model port → local loopback port currently forwarded over SSH.
    var forwardedPorts: [Int: Int] = [:]
    /// Side-panel force-update progress (agent push + reconnect + hard refresh).
    var forceUpdatePhase: GatewayForceUpdatePhase = .idle
    @ObservationIgnored var forwardSyncTask: Task<Void, Never>?
    @ObservationIgnored var forceUpdateTask: Task<Void, Never>?

    init(config: GatewayConfig, store: SwitchboardStore, tunnel: SSHTunnelManager?) {
        self.id = config.id
        self.config = config
        self.store = store
        self.tunnel = tunnel
    }

    var name: String { config.name }

    /// Update stored config without rebuilding the store/tunnel (label renames).
    func applyConfigPreservingConnection(_ config: GatewayConfig) {
        self.config = config
    }

    /// Settings-list status dot: tunnel first, then last refresh outcome.
    func settingsDotColor(dotOff: Color) -> Color {
        if tunnelState.isFailed { return DashboardTheme.stopRed }
        if tunnelState == .connecting { return DashboardTheme.pendingOrange }
        if store.lastError != nil { return DashboardTheme.stopRed }
        if store.lastUpdated != nil { return DashboardTheme.runningGreen }
        return dotOff
    }
}
