import Foundation
import ModelSwitchboardCore

extension SSHTunnelManager {
    struct Configuration: Equatable, Sendable {
        var sshUser: String
        var sshHost: String
        var sshPort: Int
        var remotePort: Int
        var identityFile: String?
        var identityAgent: String?

        var destination: String {
            sshUser.isEmpty ? sshHost : "\(sshUser)@\(sshHost)"
        }

        init(ssh: GatewayConfig.Connection.SSH) {
            sshUser = ssh.sshUser
            sshHost = ssh.sshHost
            sshPort = ssh.sshPort
            remotePort = ssh.remotePort
            identityFile = ssh.identityFile
            identityAgent = ssh.identityAgent
        }

        init(
            destination: String,
            sshPort: Int = 22,
            remotePort: Int = 8877,
            identityFile: String? = nil,
            identityAgent: String? = nil
        ) {
            let parsed = GatewayConfig.normalizedDeployHost(destination)
            if let parsed, let at = parsed.firstIndex(of: "@") {
                sshUser = String(parsed[..<at])
                sshHost = String(parsed[parsed.index(after: at)...])
            } else {
                sshUser = ""
                sshHost = parsed ?? destination
            }
            self.sshPort = sshPort
            self.remotePort = remotePort
            self.identityFile = identityFile
            self.identityAgent = identityAgent
        }

        var isUnsafeDestination: Bool {
            GatewayConfig.looksLikeSSHOption(sshHost)
                || (!sshUser.isEmpty && GatewayConfig.looksLikeSSHOption(sshUser))
        }
    }
}
