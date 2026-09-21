import Foundation

extension GatewayHub {
    func tunnelLocalPortChanged(gatewayID: String, tunnelID: UUID, localPort: UInt16) {
        guard let runtime = runtime(id: gatewayID) else { return }
        guard let current = runtime.tunnel, current.instanceID == tunnelID else { return }
        let baseURL = "http://127.0.0.1:\(localPort)"
        guard runtime.store.controllerBaseURL != baseURL else { return }
        runtime.store.controllerBaseURL = baseURL
        Task { await runtime.store.refresh() }
    }
}
