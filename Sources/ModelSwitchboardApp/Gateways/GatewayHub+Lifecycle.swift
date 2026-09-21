import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    /// Connection identity: everything except the operator-facing display name.
    static func sameConnection(_ lhs: GatewayConfig, _ rhs: GatewayConfig) -> Bool {
        lhs.id == rhs.id && lhs.enabled == rhs.enabled && lhs.connection == rhs.connection
    }

    func syncAuthToken(onto runtime: GatewayRuntime) {
        let token = tokenStorageFactory(runtime.id).load() ?? ""
        guard runtime.store.controllerAuthToken != token else { return }
        runtime.store.controllerAuthToken = token
        Task { await runtime.store.refresh() }
    }
}
