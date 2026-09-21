import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    /// Accept `user@host` or a bare ssh-config alias.
    static func parseDeployDestination(_ explicit: String) -> (user: String, host: String) {
        guard !explicit.isEmpty else { return ("", "") }
        if let at = explicit.firstIndex(of: "@"), at != explicit.startIndex,
           explicit.index(after: at) < explicit.endIndex
        {
            return (String(explicit[..<at]), String(explicit[explicit.index(after: at)...]))
        }
        return ("", explicit)
    }
}
