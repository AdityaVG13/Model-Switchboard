import Foundation

extension GatewayConfig {
    /// Human-readable connection summary for list rows.
    public var endpointSummary: String {
        switch connection {
        case .direct(let details):
            return details.baseURL
        case .ssh(let details):
            let port = details.sshPort == 22 ? "" : " -p \(details.sshPort)"
            return "ssh \(details.destination)\(port) → 127.0.0.1:\(details.remotePort)"
        }
    }

    /// Tailscale IPv4 CGNAT range 100.64.0.0/10 - not covered by ATS
    /// `NSAllowsLocalNetworking`, so cleartext direct URLs must use MagicDNS.
    public static func isIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        return parts.count == 4 && parts.allSatisfy { (0...255).contains($0) }
    }

    public static func isTailscaleCGNATAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }
}
