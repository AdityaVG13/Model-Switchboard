import Foundation

extension GatewayHub {
    func tunnelStateChanged(
        gatewayID: String,
        tunnelID: UUID,
        state: SSHTunnelManager.State
    ) {
        guard let runtime = runtime(id: gatewayID) else { return }
        // Ignore late events from a tunnel that was replaced for this gateway.
        if let current = runtime.tunnel, current.instanceID != tunnelID {
            return
        }
        runtime.tunnelState = state
        switch state {
        case .established:
            // (Re)start the refresh loop now that requests can get through, and
            // keep model-endpoint forwards aligned with running profiles.
            runtime.store.startAutoRefresh()
            startForwardSync(for: runtime)
        case .failed(let message):
            runtime.store.applyBootstrapDiagnostic(message)
            runtime.store.stopAutoRefresh()
            clearForwards(on: runtime)
        case .connecting, .idle:
            // Don't keep polling a dead/not-yet-ready forward.
            if state == .idle {
                runtime.store.stopAutoRefresh()
            }
            clearForwards(on: runtime)
        }
    }
}
