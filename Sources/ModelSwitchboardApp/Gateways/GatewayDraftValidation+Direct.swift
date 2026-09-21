import Foundation
import ModelSwitchboardCore

extension GatewayDraftValidation {
    static func validateDirect(
        draft: GatewayConfig,
        direct: inout GatewayConfig.Connection.Direct,
        name: String
    ) -> Outcome {
        direct.baseURL = direct.baseURL.whitespaceTrimmed
        guard let url = URL(string: direct.baseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host
        else {
            return .invalid("Controller URL must be an http(s) URL.")
        }
        // ATS allows .ts.net and RFC1918 local networking - not Tailscale
        // CGNAT IPs. Prefer MagicDNS (or SSH) for cleartext agent HTTP.
        if scheme == "http", GatewayConfig.isTailscaleCGNATAddress(host) {
            return .invalid("Use the host's MagicDNS name (.ts.net) for Tailscale direct mode - raw 100.x addresses are blocked by App Transport Security.")
        }
        return .valid(
            GatewayConfig.direct(
                id: draft.id,
                name: name,
                baseURL: direct.baseURL,
                remotePort: direct.remotePort,
                deployHost: direct.deployHost,
                enabled: draft.enabled
            )
        )
    }
}
