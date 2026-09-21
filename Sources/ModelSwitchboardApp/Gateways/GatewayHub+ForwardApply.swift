import Foundation

extension GatewayHub {
    func applySyncedForwards(
        _ forwarded: [Int: Int],
        to runtime: GatewayRuntime,
        tunnelID: UUID
    ) -> Bool {
        // A cancelled / replaced tunnel must not repopulate forwardedPorts
        // with stale specs (Copy Endpoint would lie).
        guard !Task.isCancelled else { return false }
        guard isLiveForwardTunnel(runtime, tunnelID: tunnelID) else { return false }
        applyForwardedPorts(forwarded, to: runtime)
        return true
    }

    func clearForwards(on runtime: GatewayRuntime) {
        runtime.forwardSyncTask?.cancel()
        runtime.forwardSyncTask = nil
        runtime.forwardedPorts = [:]
    }
}
