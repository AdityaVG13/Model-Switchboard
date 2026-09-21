import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    /// SSH target for pushing the bundled agent. SSH gateways deploy as-is;
    /// for DIRECT gateways the explicit Deploy host (an ssh-config alias)
    /// wins, then the URL hostname - which hangs forever on hosts that
    /// require Tailscale SSH re-auth.
    /// Returns `Connection.SSH` rather than minting a fake SSH-kind gateway.
    static func agentDeployTarget(for config: GatewayConfig) -> GatewayConfig.Connection.SSH? {
        switch config.connection {
        case .ssh(let ssh):
            return sshDeployTarget(ssh)
        case .direct(let direct):
            return directDeployTarget(direct)
        }
    }

    static func directDeployTarget(
        _ direct: GatewayConfig.Connection.Direct
    ) -> GatewayConfig.Connection.SSH? {
        let explicit = direct.deployHost.nonEmptyTrimmed ?? ""
        let parsed = parseDeployDestination(explicit)
        let host = parsed.host.isEmpty
            ? (URL(string: direct.baseURL)?.host.nonEmptyTrimmed ?? "")
            : parsed.host
        guard !host.isEmpty else { return nil }
        let ssh = GatewayConfig.Connection.SSH(
            sshUser: parsed.user,
            sshHost: host,
            remotePort: direct.remotePort
        )
        guard !ssh.hasUnsafeDestination else { return nil }
        return ssh
    }
}
