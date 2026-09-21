import Foundation
import ModelSwitchboardCore
import OSLog

extension RemoteAgentDeployer {
    func preparedSSHProcess(
        ssh: GatewayConfig.Connection.SSH,
        remoteCommand: String
    ) -> (Process, Pipe, Pipe, Pipe) {
        let arguments = SSHInvocation.arguments(
            to: SSHInvocation.Target(ssh),
            extraOptions: ["-o", "ConnectTimeout=10"],
            remoteCommand: remoteCommand
        )
        return configuredSSHProcess(arguments: arguments)
    }
}
