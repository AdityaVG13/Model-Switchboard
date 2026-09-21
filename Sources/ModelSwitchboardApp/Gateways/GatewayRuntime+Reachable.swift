import Foundation
import ModelSwitchboardCore

extension GatewayRuntime {
    /// A URL for this profile that is valid from this Mac, or nil when the
    /// endpoint is only reachable on the remote host.
    func reachableEndpointURL(for status: ModelProfileStatus) -> String? {
        switch config.connection {
        case .ssh:
            return sshReachableEndpointURL(for: status)
        case .direct(let direct):
            return directReachableEndpointURL(for: status, controllerBaseURL: direct.baseURL)
        }
    }
}
