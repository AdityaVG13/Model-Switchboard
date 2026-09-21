import Foundation
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func deployAgent(config: GatewayConfig) {
        deployState = .running
        Task {
            let deployer = RemoteAgentDeployer()
            do {
                guard case .ssh(let ssh) = config.connection else { return }
                let result = try await deployer.deploy(to: ssh, useTailscale: deployWithTailscale)
                await applyDeployResult(config: config, ssh: ssh, result: result)
            } catch let error as RemoteAgentDeployer.DeployError {
                switch error {
                case .missingResources:
                    deployState = .failure("This build is missing the bundled agent. Reinstall the app, or use the one-liner instead.")
                case .sshFailed:
                    deployState = .failure(error.userFacingMessage(verb: "Install"))
                }
            } catch {
                deployState = .failure(
                    UserFacingControllerError.description(for: error, isLocal: false)
                        .map { "Install failed: \($0)" }
                        ?? "Install failed."
                )
            }
        }
    }
}
