import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func waitForForceUpdateTunnel(id: String) async {
        // Wait briefly for the replacement tunnel; refresh starts on .established.
        for _ in 0..<40 {
            if Task.isCancelled { return }
            guard let live = runtime(id: id) else { return }
            if live.tunnelState.isEstablished || live.tunnelState.isFailed { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func refreshForceUpdatedRuntime(gatewayID: String) async {
        guard let live = runtime(id: gatewayID) else { return }
        live.forceUpdatePhase = .updating("Refreshing…")
        let lastMessage = await pollForceUpdateRefresh(live)
        if Task.isCancelled { return }
        if live.store.refreshState == .refreshed {
            live.forceUpdatePhase = .idle
            return
        }
        live.forceUpdatePhase = .failed(
            "Agent updated, but the host is not answering yet: \(lastMessage ?? "refresh failed")"
        )
    }
}
