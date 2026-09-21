import Foundation
import ModelSwitchboardCore

extension GatewayDraftValidation {
    static func validateSSH(
        draft: GatewayConfig,
        ssh: inout GatewayConfig.Connection.SSH,
        name: String
    ) -> Outcome {
        ssh.sshHost = ssh.sshHost.whitespaceTrimmed
        ssh.sshUser = ssh.sshUser.whitespaceTrimmed
        if ssh.sshHost.isEmpty {
            return .invalid("SSH host is required.")
        }
        let candidate = GatewayConfig.ssh(
            id: draft.id,
            name: name,
            sshUser: ssh.sshUser,
            sshHost: ssh.sshHost,
            sshPort: ssh.sshPort,
            remotePort: ssh.remotePort,
            identityFile: ssh.identityFile,
            identityAgent: ssh.identityAgent,
            enabled: draft.enabled
        )
        if ssh.hasUnsafeDestination {
            return .invalid("SSH user/host cannot start with '-' (would be parsed as an ssh option).")
        }
        guard TCPPort.isValid(ssh.sshPort) else {
            return .invalid("SSH port must be between 1 and 65535.")
        }
        guard TCPPort.isValid(candidate.remotePort) else {
            return .invalid("Agent port must be between 1 and 65535.")
        }
        return .valid(candidate)
    }
}
