import Foundation
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @MainActor
    func applyDeployResult(
        config: GatewayConfig,
        ssh: GatewayConfig.Connection.SSH,
        result: RemoteAgentDeployer.Result
    ) {
        if applyTailscaleDeployConversion(config: config, result: result) {
            return
        }
        rememberDeployAuthToken(result.authToken)
        deployState = .success(
            "Agent installed on \(ssh.sshHost).\(deploySuccessSuffix(pairingLink: result.pairingLink)) Save the gateway to connect."
        )
    }

    @MainActor
    func rememberDeployAuthToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        draftToken = token
    }
}
