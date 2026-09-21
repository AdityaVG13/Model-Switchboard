import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func failMissingDeployTarget(_ runtime: GatewayRuntime) async {
        runtime.forceUpdatePhase = .failed(
            "Add an SSH user/host in Settings for this gateway, then click Update to push a fresh agent from this Mac."
        )
        await runtime.store.refresh()
    }

    func finishForceUpdate(gatewayID: String) async {
        guard !Task.isCancelled else { return }
        guard let current = self.runtime(id: gatewayID) else { return }
        await reconnectForceUpdatedRuntime(current)
        await refreshForceUpdatedRuntime(gatewayID: gatewayID)
    }
}
