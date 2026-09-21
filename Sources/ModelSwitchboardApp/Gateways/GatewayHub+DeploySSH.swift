import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    static func sshDeployTarget(_ ssh: GatewayConfig.Connection.SSH) -> GatewayConfig.Connection.SSH? {
        guard ssh.sshHost.nonEmptyTrimmed != nil else {
            return nil
        }
        guard !ssh.hasUnsafeDestination else { return nil }
        return ssh
    }
}
