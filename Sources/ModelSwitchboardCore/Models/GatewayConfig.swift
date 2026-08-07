import Foundation

/// How the app reaches a remote gateway's controller endpoint.
public enum GatewayKind: String, Codable, Sendable {
    /// The controller URL is reachable as-is (LAN or user-managed tunnel).
    case direct
    /// The app opens an SSH tunnel to the remote host's loopback controller.
    case ssh
}

/// A named controller endpoint managed from the dashboard.
///
/// The local gateway is never persisted here: it is synthesized so its base URL
/// and token keep flowing from the pre-gateway UserDefaults/Keychain locations.
public struct GatewayConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: GatewayKind
    /// Direct gateways only: the controller base URL, e.g. `http://spark.local:8877`.
    public var baseURL: String
    public var sshUser: String
    public var sshHost: String
    public var sshPort: Int
    /// Port the agent listens on at the remote host's loopback.
    public var remotePort: Int
    /// Optional private key path passed to `ssh -i`.
    public var identityFile: String?
    /// Optional `IdentityAgent` socket (1Password, custom agents); GUI apps do
    /// not inherit a shell's SSH_AUTH_SOCK.
    public var identityAgent: String?
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: GatewayKind,
        baseURL: String = "",
        sshUser: String = "",
        sshHost: String = "",
        sshPort: Int = 22,
        remotePort: Int = 8877,
        identityFile: String? = nil,
        identityAgent: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.sshUser = sshUser
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.remotePort = remotePort
        self.identityFile = identityFile
        self.identityAgent = identityAgent
        self.enabled = enabled
    }

    public var sshDestination: String {
        sshUser.isEmpty ? sshHost : "\(sshUser)@\(sshHost)"
    }

    /// OpenSSH treats argv tokens starting with `-` as options. Reject those
    /// for host/user so pasted pairing codes and settings cannot inject flags.
    public var hasUnsafeSSHDestination: Bool {
        Self.looksLikeSSHOption(sshHost) || (!sshUser.isEmpty && Self.looksLikeSSHOption(sshUser))
    }

    public static func looksLikeSSHOption(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-")
    }

    /// Human-readable connection summary for list rows.
    public var endpointSummary: String {
        switch kind {
        case .direct:
            return baseURL
        case .ssh:
            let destination = sshDestination
            let port = sshPort == 22 ? "" : " -p \(sshPort)"
            return "ssh \(destination)\(port) → 127.0.0.1:\(remotePort)"
        }
    }

    /// Tailscale IPv4 CGNAT range 100.64.0.0/10 — not covered by ATS
    /// `NSAllowsLocalNetworking`, so cleartext direct URLs must use MagicDNS.
    public static func isTailscaleCGNATAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }
}

/// The identity a `SwitchboardStore` runs under.
public struct GatewayContext: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isLocal: Bool

    public init(id: String, name: String, isLocal: Bool) {
        self.id = id
        self.name = name
        self.isLocal = isLocal
    }

    public static let local = GatewayContext(id: "local", name: "This Mac", isLocal: true)

    public init(config: GatewayConfig) {
        self.init(id: config.id, name: config.name, isLocal: false)
    }
}

/// Parses pairing codes printed by `model-switchboard-agent link` on the
/// remote host:
/// - SSH tunnel: `modelswitchboard-gateway://user@host?name=spark&agent_port=8877`
/// - Direct (e.g. Tailscale MagicDNS): `modelswitchboard-gateway://spark.tail1234.ts.net?name=spark&agent_port=8877&mode=direct`
public enum GatewayLinkCode {
    public static let scheme = "modelswitchboard-gateway"

    public static func parse(_ raw: String) -> GatewayConfig? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == scheme,
            let host = components.host, !host.isEmpty,
            !GatewayConfig.looksLikeSSHOption(host)
        else { return nil }
        if let user = components.user, GatewayConfig.looksLikeSSHOption(user) {
            return nil
        }
        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }
        let name = value("name").flatMap { $0.isEmpty ? nil : $0 } ?? host
        let agentPort = value("agent_port").flatMap(Int.init) ?? 8877
        guard (1...65535).contains(agentPort) else { return nil }
        let sshPort = components.port ?? 22
        guard (1...65535).contains(sshPort) else { return nil }
        if value("mode")?.lowercased() == "direct" {
            return GatewayConfig(
                name: name,
                kind: .direct,
                baseURL: "http://\(host):\(agentPort)",
                remotePort: agentPort
            )
        }
        return GatewayConfig(
            name: name,
            kind: .ssh,
            sshUser: components.user ?? "",
            sshHost: host,
            sshPort: sshPort,
            remotePort: agentPort
        )
    }
}

/// Persists remote gateway configurations as JSON in UserDefaults.
public enum GatewayConfigStore {
    public static let defaultsKey = "modelswitchboard.gateways.v1"
    public static let corruptBackupKey = "modelswitchboard.gateways.v1.corrupt"

    public enum LoadResult: Equatable {
        case missing
        case loaded([GatewayConfig])
        /// On-disk blob failed to decode. Callers must not treat this as an
        /// intentional empty list and must not persist `[]` over the blob.
        case corrupt
    }

    public static func loadResult(from defaults: UserDefaults = .standard) -> LoadResult {
        guard let data = defaults.data(forKey: defaultsKey) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode([GatewayConfig].self, from: data))
        } catch {
            if defaults.data(forKey: corruptBackupKey) == nil {
                defaults.set(data, forKey: corruptBackupKey)
            }
            return .corrupt
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> [GatewayConfig] {
        switch loadResult(from: defaults) {
        case .missing, .corrupt:
            return []
        case .loaded(let gateways):
            return gateways
        }
    }

    public static func save(_ gateways: [GatewayConfig], to defaults: UserDefaults = .standard) {
        // Never clobber a corrupt blob with an accidental empty write — that
        // permanently deletes every remote gateway after a schema glitch.
        if gateways.isEmpty, case .corrupt = loadResult(from: defaults) {
            return
        }
        guard let data = try? JSONEncoder().encode(gateways) else { return }
        defaults.set(data, forKey: defaultsKey)
        defaults.removeObject(forKey: corruptBackupKey)
    }
}
