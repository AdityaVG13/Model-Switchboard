import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    struct Result: Sendable, Equatable {
        let pairingLink: String?
        /// Bearer token printed by the Tailscale installer (empty for unauthenticated installs).
        let authToken: String?
        let log: String
    }

    enum DeployError: Error, Equatable {
        case missingResources
        case sshFailed(step: String, message: String)

        func userFacingMessage(verb: String) -> String {
            switch self {
            case .missingResources:
                return "This build is missing the bundled agent."
            case .sshFailed(let step, let message):
                return "\(verb) failed while trying to \(step): \(message)"
            }
        }
    }
}
