import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    /// Pushes the agent modules and runs the installer on the gateway host. With
    /// `useTailscale` the agent is set up bound to the host's tailnet address
    /// and the returned pairing link describes a direct (tunnel-less) gateway.
    func deploy(
        to ssh: GatewayConfig.Connection.SSH,
        useTailscale: Bool = false,
        profilesDirectory: String? = nil
    ) async throws -> Result {
        guard resourcesAvailable else { throw DeployError.missingResources }
        if ssh.hasUnsafeDestination {
            throw DeployError.sshFailed(
                step: "validate",
                message: "SSH user/host cannot start with '-' (would be parsed as an ssh option)."
            )
        }
        let installerData = try Data(contentsOf: installerURL)
        try await pushAgentModules(to: ssh)

        // 2. Run the installer from stdin: no files land anywhere except the
        //    agent's own install root.
        let invocation = installerInvocation(
            remotePort: ssh.remotePort,
            useTailscale: useTailscale,
            profilesDirectory: profilesDirectory
        )
        let output = try await runSSH(
            ssh: ssh,
            step: "run installer",
            remoteCommand: "\(invocation.prefix)bash -s -- \(invocation.flags)",
            stdin: installerData
        )

        let pairingLink = pairingLink(from: output)
        let authToken = Self.extractAuthToken(from: output)
        return Result(pairingLink: pairingLink, authToken: authToken, log: output)
    }
}
