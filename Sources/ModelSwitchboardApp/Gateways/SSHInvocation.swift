import Foundation
import ModelSwitchboardCore

/// Shared OpenSSH argv for BatchMode connections.
///
/// Tunnel and deploy add their own prefix/timeout flags. Neither may omit
/// `--` before the destination, or rewrite BatchMode / identity / port.
enum SSHInvocation {
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

    /// `prefix` + BatchMode + `extraOptions` + port/identity + `-- dest` [+ command].
    static func arguments(
        to target: Target,
        prefix: [String] = [],
        extraOptions: [String] = [],
        remoteCommand: String? = nil
    ) -> [String] {
        var arguments = prefix
        arguments += ["-o", "BatchMode=yes"]
        arguments += extraOptions
        if target.sshPort != 22 {
            arguments += ["-p", String(target.sshPort)]
        }
        if let identityFile = target.identityFile, !identityFile.isEmpty {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        if let identityAgent = target.identityAgent, !identityAgent.isEmpty {
            arguments += ["-o", "IdentityAgent=\(identityAgent)"]
        }
        arguments += ["--", target.destination]
        if let remoteCommand, !remoteCommand.isEmpty {
            arguments.append(remoteCommand)
        }
        return arguments
    }
}
