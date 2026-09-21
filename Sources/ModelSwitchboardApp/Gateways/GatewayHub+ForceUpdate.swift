import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    /// Push the bundled agent (when SSH is available), bounce the tunnel, and
    /// hard-refresh status so stale ports/models cannot linger on the Mac UI.
    func forceUpdateGateway(id: String) async {
        guard let runtime = runtime(id: id) else { return }
        if runtime.forceUpdatePhase.isUpdating { return }
        runtime.forceUpdateTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performForceUpdate(gatewayID: id)
        }
        runtime.forceUpdateTask = task
        _ = await task.value
    }

    func performForceUpdate(gatewayID: String) async {
        guard let runtime = runtime(id: gatewayID) else { return }
        guard let deployTarget = Self.agentDeployTarget(for: runtime.config) else {
            await failMissingDeployTarget(runtime)
            return
        }
        // Keep the live board visible. Discarding first made Retry blank the
        // menu bar and then bounce a working tunnel when deploy failed.
        runtime.forceUpdatePhase = .updating("Pushing agent…")
        guard await pushForceUpdateAgent(gatewayID: gatewayID, runtime: runtime, deployTarget: deployTarget) else {
            return
        }
        await finishForceUpdate(gatewayID: gatewayID)
    }
}
