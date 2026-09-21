import Foundation
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @MainActor
    func applyTailscaleDeployConversion(
        config: GatewayConfig,
        result: RemoteAgentDeployer.Result
    ) -> Bool {
        guard deployWithTailscale,
              let link = result.pairingLink,
              var direct = GatewayLinkCode.parse(link),
              direct.kind == .direct else {
            return false
        }
        direct.id = config.id
        if config.name.nonEmptyWhitespaceTrimmed != nil {
            direct.name = config.name
        }
        if let deployHost = config.ssh?.sshHost.trimmed.nonEmptyTrimmed,
           case .direct(var payload) = direct.connection {
            payload.deployHost = deployHost
            direct.connection = .direct(payload)
        }
        draft = direct
        rememberDeployAuthToken(result.authToken)
        let urlText = direct.direct?.baseURL ?? ""
        deployState = .success(
            "Agent installed in Tailscale mode - gateway switched to direct URL \(urlText).\(tailscaleTokenHint(authToken: result.authToken)) Save to connect."
        )
        return true
    }
}
