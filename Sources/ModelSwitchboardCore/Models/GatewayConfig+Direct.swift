import Foundation

extension GatewayConfig.Connection {
    public struct Direct: Equatable, Sendable {
        /// Controller base URL, e.g. `http://gpu.example:8877`.
        public var baseURL: String
        /// Port the agent listens on at the remote host's loopback.
        /// Mirrored in `baseURL`'s port; kept as a field because the
        /// deploy path pushes the agent with `--port` and must not
        /// re-derive it from the URL text.
        public var remotePort: Int
        /// SSH destination used only to push agent updates (e.g. an
        /// ssh-config alias). Defaults to the URL's host, which hangs
        /// forever when that host requires Tailscale SSH re-auth.
        public var deployHost: String?

        public init(baseURL: String, remotePort: Int = 8877, deployHost: String? = nil) {
            self.baseURL = baseURL
            if let urlPort = URL(string: baseURL)?.port {
                self.remotePort = urlPort
            } else {
                self.remotePort = remotePort
            }
            self.deployHost = GatewayConfig.normalizedDeployHost(deployHost)
        }
    }
}
