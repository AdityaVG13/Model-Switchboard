import Foundation
import ModelSwitchboardCore

extension SSHInvocation {
    /// Shared OpenSSH argv for BatchMode connections.
    ///
    /// Tunnel and deploy add their own prefix/timeout flags. Neither may omit
    /// `--` before the destination, or rewrite BatchMode / identity / port.
    struct Target: Equatable, Sendable {
        var destination: String
        var sshPort: Int
        var identityFile: String?
        var identityAgent: String?

        init(
            destination: String,
            sshPort: Int = 22,
            identityFile: String? = nil,
            identityAgent: String? = nil
        ) {
            self.destination = destination
            self.sshPort = sshPort
            self.identityFile = identityFile
            self.identityAgent = identityAgent
        }

        init(_ ssh: GatewayConfig.Connection.SSH) {
            self.init(
                destination: ssh.destination,
                sshPort: ssh.sshPort,
                identityFile: ssh.identityFile,
                identityAgent: ssh.identityAgent
            )
        }
    }
}
