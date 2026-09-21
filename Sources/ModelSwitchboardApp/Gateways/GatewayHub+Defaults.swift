import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    /// Closure instead of `?? Self.makeRemoteStore`: storing that static method
    /// as a value tripped GitHub Actions' Swift as a nonisolated call to a
    /// MainActor function.
    static func defaultRemoteStoreFactory() -> RemoteStoreFactory {
        { config, baseURL, token in
            GatewayHub.makeRemoteStore(config: config, baseURL: baseURL, token: token)
        }
    }

    static func defaultDeployAgent() -> @MainActor (
        GatewayConfig.Connection.SSH, Bool, String?
    ) async throws -> RemoteAgentDeployer.Result {
        { ssh, useTailscale, profilesDirectory in
            try await RemoteAgentDeployer().deploy(
                to: ssh, useTailscale: useTailscale, profilesDirectory: profilesDirectory)
        }
    }
}
