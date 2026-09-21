import Foundation

extension GatewayHub {
    func startForwardSync(for runtime: GatewayRuntime) {
        runtime.forwardSyncTask?.cancel()
        guard let tunnel = runtime.tunnel else { return }
        let tunnelID = tunnel.instanceID
        runtime.forwardSyncTask = Task { [weak runtime] in
            while !Task.isCancelled {
                guard let runtime else { return }
                guard await syncForwardsOnce(runtime, tunnel: tunnel, tunnelID: tunnelID) else { return }
                try? await Task.sleep(for: .seconds(Self.forwardSyncIntervalSeconds))
            }
        }
    }

    func syncForwardsOnce(
        _ runtime: GatewayRuntime,
        tunnel: SSHTunnelManager,
        tunnelID: UUID
    ) async -> Bool {
        guard isLiveForwardTunnel(runtime, tunnelID: tunnelID) else { return false }
        let forwarded = await tunnel.syncForwards(remotePorts: runningForwardPorts(in: runtime))
        return applySyncedForwards(forwarded, to: runtime, tunnelID: tunnelID)
    }
}
