import Foundation

extension GatewayConfig {
    public enum Connection: Equatable, Sendable {
        /// The controller URL is reachable as-is (LAN or user-managed tunnel).
        case direct(Direct)
        /// The app opens an SSH tunnel to the remote host's loopback controller.
        case ssh(SSH)
    }
}
