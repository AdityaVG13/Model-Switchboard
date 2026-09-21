import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    /// HTTP timeouts for remote agent status/doctor/action calls.
    ///
    /// Connect failures still fail fast (`waitsForConnectivity = false`). These
    /// bounds cover a cold `/api/status` while the agent inventories listeners
    /// and probes claimed ports. Values that are too tight (historically 5s/15s)
    /// surface as permanent `DIRECT · ERROR` / "Request timed out" even when the
    /// agent is healthy - discovery of a busy vLLM host regularly exceeds 5s.
    enum RemoteHTTPTimeouts {
        static let request: TimeInterval = 45
        static let resource: TimeInterval = 90
    }

    @MainActor
    static func makeRemoteStore(
        config: GatewayConfig, baseURL: String, token: String
    ) -> SwitchboardStore {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = RemoteHTTPTimeouts.request
        sessionConfiguration.timeoutIntervalForResource = RemoteHTTPTimeouts.resource
        sessionConfiguration.waitsForConnectivity = false
        // Bypass system HTTP(S) proxies so tunnel loopback / Tailscale direct
        // agent traffic cannot be diverted off-box.
        sessionConfiguration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfiguration)
        return SwitchboardStore(
            controllerBaseURL: baseURL,
            controllerAuthToken: token,
            // Inherit the app edition so Plus can benchmark remote models.
            features: .current,
            gateway: GatewayContext(config: config),
            autoStartRefresh: config.kind == .direct,
            controllerClientFactory: { baseURLString, authToken in
                try ControllerClient(baseURLString: baseURLString, authToken: authToken, session: session)
            }
        )
    }
}
