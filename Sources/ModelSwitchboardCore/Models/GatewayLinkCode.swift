import Foundation

/// Parses pairing codes printed by `model-switchboard-agent link` on the
/// remote host. The `mode` query token is the single kind signal on the wire:
/// - SSH tunnel: `modelswitchboard-gateway://user@host?name=gpu&agent_port=8877&mode=ssh`
/// - Direct (e.g. Tailscale MagicDNS): `modelswitchboard-gateway://host.example.ts.net?name=gpu&agent_port=8877&mode=direct`
/// The kind is never re-derived from the URL shape (user@host presence); the
/// only legacy fallback is a missing `mode` on links printed before the token
/// existed, which default to `.ssh` here at the boundary.
public enum GatewayLinkCode {
    public static let scheme = "modelswitchboard-gateway"

    static func queryValue(_ query: [URLQueryItem], _ name: String) -> String? {
        query.first { $0.name == name }?.value
    }

    static func isValidPort(_ port: Int) -> Bool {
        TCPPort.isValid(port)
    }
}
