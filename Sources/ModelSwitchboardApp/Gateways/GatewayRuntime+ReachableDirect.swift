import Foundation
import ModelSwitchboardCore

extension GatewayRuntime {
    func directReachableEndpointURL(
        for status: ModelProfileStatus,
        controllerBaseURL: String
    ) -> String? {
        if !status.usesLoopbackEndpoint {
            return status.baseURL
        }
        // Agent status always advertises loopback `base_url` unless BASE_URL
        // is set. Rewriting that to the controller's LAN/tailnet host only
        // works when the model process itself is bound beyond loopback
        // (HOST=0.0.0.0 / a real interface). A default 127.0.0.1 bind stays
        // remote-only - Copy Endpoint would otherwise hand out a dead URL.
        guard !LoopbackHost.isLoopback(status.host) else { return nil }
        guard
            let controllerHost = URL(string: controllerBaseURL)?.host,
            !LoopbackHost.isLoopback(controllerHost),
            var components = URLComponents(string: status.baseURL)
        else { return nil }
        components.host = controllerHost
        return components.url?.absoluteString
    }
}
