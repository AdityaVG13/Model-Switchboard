import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func reconnectForceUpdatedRuntime(_ current: GatewayRuntime) async {
        guard current.config.kind == .ssh else { return }
        current.forceUpdatePhase = .updating("Reconnecting…")
        bounceSSHRuntime(id: current.id, preservingPhase: current.forceUpdatePhase)
        await waitForForceUpdateTunnel(id: current.id)
    }

    func bounceSSHRuntime(id: String, preservingPhase: GatewayForceUpdatePhase) {
        guard let index = runtimeIndex(id: id) else { return }
        let old = remoteRuntimes[index]
        let config = old.config
        teardown(old)
        let fresh = makeRuntime(config: config)
        fresh.forceUpdatePhase = preservingPhase
        remoteRuntimes[index] = fresh
    }
}
