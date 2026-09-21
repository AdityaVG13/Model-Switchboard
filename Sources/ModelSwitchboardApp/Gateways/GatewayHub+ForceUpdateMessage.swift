import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func forceUpdateDeployMessage(_ error: Error) -> String {
        if let deployError = error as? RemoteAgentDeployer.DeployError {
            return deployError.userFacingMessage(verb: "Agent update")
        }
        return UserFacingControllerError.description(for: error, isLocal: false)
            ?? "Agent update failed."
    }
}
