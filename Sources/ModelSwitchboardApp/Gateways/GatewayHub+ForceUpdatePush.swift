import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func pushForceUpdateAgent(
        gatewayID: String,
        runtime: GatewayRuntime,
        deployTarget: GatewayConfig.Connection.SSH
    ) async -> Bool {
        let config = runtime.config
        // Direct (Tailscale) installs bind the agent to the tailnet; SSH
        // tunnel installs keep loopback-only listen + Mac-side forward.
        let useTailscale = config.kind == .direct
        let profilesDirectory = runtime.store.profilesDirectory.nonEmptyTrimmed
        do {
            let result = try await deployAgent(deployTarget, useTailscale, profilesDirectory)
            if let token = result.authToken.nonEmptyTrimmed {
                tokenStorageFactory(config.id).save(token)
                if let live = self.runtime(id: gatewayID) {
                    live.store.controllerAuthToken = token
                }
            }
            return true
        } catch {
            let message = forceUpdateDeployMessage(error)
            if let live = self.runtime(id: gatewayID) {
                live.forceUpdatePhase = .failed(message)
                await live.store.refresh()
            }
            Self.logger.error("force-update deploy failed: \(message, privacy: .public)")
            return false
        }
    }
}
