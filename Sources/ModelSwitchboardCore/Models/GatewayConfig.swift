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
            let host = components.host, !host.isEmpty
        else { return nil }
        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }
        let name = value("name").flatMap { $0.isEmpty ? nil : $0 } ?? host
        let agentPort = value("agent_port").flatMap(Int.init) ?? 8877
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
            sshPort: components.port ?? 22,
            remotePort: agentPort
        )
    }
}

/// Persists remote gateway configurations as JSON in UserDefaults.
public enum GatewayConfigStore {
    public static let defaultsKey = "modelswitchboard.gateways.v1"

    public static func load(from defaults: UserDefaults = .standard) -> [GatewayConfig] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([GatewayConfig].self, from: data)) ?? []
    }

    public static func save(_ gateways: [GatewayConfig], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(gateways) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
