import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func makeRuntime(config: GatewayConfig) -> GatewayRuntime {
        let token = tokenStorageFactory(config.id).load() ?? ""
        switch config.connection {
        case .direct(let direct):
            let store = remoteStoreFactory(config, direct.baseURL, token)
            return GatewayRuntime(config: config, store: store, tunnel: nil)
        case .ssh(let ssh):
            return makeSSHRuntime(config: config, ssh: ssh, token: token)
        }
    }
}
