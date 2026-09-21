import Foundation

extension GatewayConfig {
    public var kind: GatewayKind {
        switch connection {
        case .direct: return .direct
        case .ssh: return .ssh
        }
    }

    /// SSH payload when this gateway is an SSH tunnel; `nil` for direct.
    /// Prefer switching on `connection` at call sites that already branch.
    public var ssh: Connection.SSH? {
        if case .ssh(let details) = connection { return details }
        return nil
    }

    /// Direct payload when this gateway is a URL; `nil` for SSH.
    public var direct: Connection.Direct? {
        if case .direct(let details) = connection { return details }
        return nil
    }

    /// Both kinds carry the remote agent port.
    public var remotePort: Int {
        switch connection {
        case .direct(let details): return details.remotePort
        case .ssh(let details): return details.remotePort
        }
    }

    public static func looksLikeSSHOption(_ value: String) -> Bool {
        value.trimmed.hasPrefix("-")
    }

    /// Parse `user@host` or bare host at the boundary. `user@host@extra`,
    /// `user@`, and `@host` are unrepresentable (nil).
    public static func normalizedDeployHost(_ raw: String?) -> String? {
        guard let trimmed = raw?.nonEmptyTrimmed else { return nil }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        if parts.contains(where: \.isEmpty) { return nil }
        if parts.count == 1 { return parts[0] }
        if parts.count == 2 { return "\(parts[0])@\(parts[1])" }
        return nil
    }
}
