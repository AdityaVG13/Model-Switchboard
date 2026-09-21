import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func makeSSHRuntime(
        config: GatewayConfig,
        ssh: GatewayConfig.Connection.SSH,
        token: String
    ) -> GatewayRuntime {
        let hubReference = WeakHub(self)
        let tunnel = SSHTunnelManager(
            gatewayID: config.id,
            configuration: .init(ssh: ssh),
            executableURL: sshExecutableURL,
            onStateChange: { tunnelID, state in
                await hubReference.value?.tunnelStateChanged(
                    gatewayID: config.id,
                    tunnelID: tunnelID,
                    state: state
                )
            },
            onLocalPortChange: { tunnelID, port in
                await hubReference.value?.tunnelLocalPortChanged(
                    gatewayID: config.id,
                    tunnelID: tunnelID,
                    localPort: port
                )
            }
        )
        let store = remoteStoreFactory(config, tunnel.localBaseURL, token)
        let runtime = GatewayRuntime(config: config, store: store, tunnel: tunnel)
        Task { await tunnel.start() }
        return runtime
    }
}
