import Foundation

extension GatewayLinkCode {
    static func gateway(
        mode: String?,
        name: String,
        host: String,
        user: String?,
        sshPort: Int,
        agentPort: Int
    ) -> GatewayConfig? {
        switch mode {
        case "direct":
            return .direct(
                name: name,
                baseURL: "http://\(host):\(agentPort)",
                remotePort: agentPort
            )
        case "ssh", nil:
            // `nil`: legacy links (pre-mode token) are SSH-shaped.
            return .ssh(
                name: name,
                sshUser: user ?? "",
                sshHost: host,
                sshPort: sshPort,
                remotePort: agentPort
            )
        default:
            // Unknown mode token: refuse to guess a kind from the URL shape.
            return nil
        }
    }
}
