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
/// The connection facts are a **discriminated union**: a gateway is either an
/// SSH tunnel (`Connection.ssh`) or a direct URL (`Connection.direct`). The
/// kind is the single discriminator, parsed once at the boundary (link code /
/// settings form). The other kind's fields cannot be represented — a `.direct`
/// gateway can never carry an ssh host and an `.ssh` gateway can never carry a
/// base URL — so the old open product (`.direct` + `sshHost` set, kind
/// switched in the form leaving dead fields behind) no longer exists.
///
/// The local gateway is never persisted here: it is synthesized so its base URL
/// and token keep flowing from the pre-gateway UserDefaults/Keychain locations.
///
/// Legacy note (persistence): UserDefaults blobs written before this collapse
/// contain every field for every kind. The decoder reads only the active
/// kind's keys and ignores the dead ones; the encoder writes only the active
/// kind's keys, so a gateway is shrunk to its legal shape on the next save.
public struct GatewayConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var connection: Connection

    public enum Connection: Equatable, Sendable {
        /// The controller URL is reachable as-is (LAN or user-managed tunnel).
        case direct(Direct)
        /// The app opens an SSH tunnel to the remote host's loopback controller.
        case ssh(SSH)

        public struct Direct: Equatable, Sendable {
            /// Controller base URL, e.g. `http://spark.local:8877`.
            public var baseURL: String
            /// Port the agent listens on at the remote host's loopback.
            /// Mirrored in `baseURL`'s port; kept as a field because the
            /// deploy path pushes the agent with `--port` and must not
            /// re-derive it from the URL text.
            public var remotePort: Int

            public init(baseURL: String, remotePort: Int = 8877) {
                self.baseURL = baseURL
                self.remotePort = remotePort
            }
        }

        public struct SSH: Equatable, Sendable {
            public var sshUser: String
            public var sshHost: String
            public var sshPort: Int
            /// Port the agent listens on at the remote host's loopback.
            public var remotePort: Int
            /// Optional private key path passed to `ssh -i`.
            public var identityFile: String?
            /// Optional `IdentityAgent` socket (1Password, custom agents); GUI
            /// apps do not inherit a shell's SSH_AUTH_SOCK.
            public var identityAgent: String?

            public init(
                sshUser: String = "",
                sshHost: String,
                sshPort: Int = 22,
                remotePort: Int = 8877,
                identityFile: String? = nil,
                identityAgent: String? = nil
            ) {
                self.sshUser = sshUser
                self.sshHost = sshHost
                self.sshPort = sshPort
                self.remotePort = remotePort
                self.identityFile = identityFile
                self.identityAgent = identityAgent
            }
        }
    }

    /// Private-by-convention construction: callers use the `direct`/`ssh`
    /// factories, which set exactly the fields their kind may carry.
    init(id: String, name: String, enabled: Bool, connection: Connection) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.connection = connection
    }

    /// SSH-tunnel gateway. Illegal combination `.direct` + ssh fields is
    /// unrepresentable: an ssh gateway carries exactly the SSH payload.
    public static func ssh(
        id: String = UUID().uuidString,
        name: String,
        sshUser: String = "",
        sshHost: String = "",
        sshPort: Int = 22,
        remotePort: Int = 8877,
        identityFile: String? = nil,
        identityAgent: String? = nil,
        enabled: Bool = true
    ) -> GatewayConfig {
        GatewayConfig(
            id: id,
            name: name,
            enabled: enabled,
            connection: .ssh(.init(
                sshUser: sshUser,
                sshHost: sshHost,
                sshPort: sshPort,
                remotePort: remotePort,
                identityFile: identityFile,
                identityAgent: identityAgent
            ))
        )
    }

    /// Direct-URL gateway. Illegal combination `.ssh` + baseURL is
    /// unrepresentable: a direct gateway carries exactly the URL payload.
    public static func direct(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        remotePort: Int = 8877,
        enabled: Bool = true
    ) -> GatewayConfig {
        GatewayConfig(
            id: id,
            name: name,
            enabled: enabled,
            connection: .direct(.init(baseURL: baseURL, remotePort: remotePort))
        )
    }

    public var kind: GatewayKind {
        switch connection {
        case .direct: return .direct
        case .ssh: return .ssh
        }
    }

    // Projections for callers that switch on `kind` first. Reading the
    // inactive kind's projection returns the old empty/default values; callers
    // only read the active kind's fields, exactly as before the collapse.

    /// Direct gateways only; `""` for SSH gateways.
    public var baseURL: String {
        if case .direct(let details) = connection { return details.baseURL }
        return ""
    }

    /// SSH gateways only; `""` for direct gateways.
    public var sshUser: String {
        if case .ssh(let details) = connection { return details.sshUser }
        return ""
    }

    /// SSH gateways only; `""` for direct gateways.
    public var sshHost: String {
        if case .ssh(let details) = connection { return details.sshHost }
        return ""
    }

    /// SSH gateways only; `22` for direct gateways.
    public var sshPort: Int {
        if case .ssh(let details) = connection { return details.sshPort }
        return 22
    }

    /// Both kinds carry the remote agent port.
    public var remotePort: Int {
        switch connection {
        case .direct(let details): return details.remotePort
        case .ssh(let details): return details.remotePort
        }
    }

    /// SSH gateways only; `nil` for direct gateways.
    public var identityFile: String? {
        if case .ssh(let details) = connection { return details.identityFile }
        return nil
    }

    /// SSH gateways only; `nil` for direct gateways.
    public var identityAgent: String? {
        if case .ssh(let details) = connection { return details.identityAgent }
        return nil
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
        switch connection {
        case .direct(let details):
            return details.baseURL
        case .ssh(let details):
            let destination = sshDestination
            let port = details.sshPort == 22 ? "" : " -p \(details.sshPort)"
            return "ssh \(destination)\(port) → 127.0.0.1:\(details.remotePort)"
        }
    }

    /// Tailscale IPv4 CGNAT range 100.64.0.0/10 — not covered by ATS
    /// `NSAllowsLocalNetworking`, so cleartext direct URLs must use MagicDNS.
    public static func isTailscaleCGNATAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    // MARK: - Codable (flat legacy-compatible wire shape)

    /// The persisted/encoded shape stays the old flat key set so existing
    /// UserDefaults blobs keep decoding. `kind` is the discriminator; only the
    /// active kind's keys are written, and foreign-kind keys in legacy blobs
    /// are ignored at decode (dropped on the next save).
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, enabled
        case baseURL, sshUser, sshHost, sshPort, remotePort, identityFile, identityAgent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        switch try container.decode(GatewayKind.self, forKey: .kind) {
        case .direct:
            // Legacy blobs may carry dead ssh keys; only the direct keys are read.
            connection = .direct(.init(
                baseURL: try container.decode(String.self, forKey: .baseURL),
                remotePort: try container.decode(Int.self, forKey: .remotePort)
            ))
        case .ssh:
            connection = .ssh(.init(
                sshUser: try container.decode(String.self, forKey: .sshUser),
                sshHost: try container.decode(String.self, forKey: .sshHost),
                sshPort: try container.decode(Int.self, forKey: .sshPort),
                remotePort: try container.decode(Int.self, forKey: .remotePort),
                identityFile: Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .identityFile)),
                identityAgent: Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .identityAgent))
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(kind, forKey: .kind)
        switch connection {
        case .direct(let details):
            try container.encode(details.baseURL, forKey: .baseURL)
            try container.encode(details.remotePort, forKey: .remotePort)
        case .ssh(let details):
            try container.encode(details.sshUser, forKey: .sshUser)
            try container.encode(details.sshHost, forKey: .sshHost)
            try container.encode(details.sshPort, forKey: .sshPort)
            try container.encode(details.remotePort, forKey: .remotePort)
            if let identityFile = Self.nonEmpty(details.identityFile) {
                try container.encode(identityFile, forKey: .identityFile)
            }
            if let identityAgent = Self.nonEmpty(details.identityAgent) {
                try container.encode(identityAgent, forKey: .identityAgent)
            }
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
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
/// remote host. The `mode` query token is the single kind signal on the wire:
/// - SSH tunnel: `modelswitchboard-gateway://user@host?name=spark&agent_port=8877&mode=ssh`
/// - Direct (e.g. Tailscale MagicDNS): `modelswitchboard-gateway://spark.tail1234.ts.net?name=spark&agent_port=8877&mode=direct`
/// The kind is never re-derived from the URL shape (user@host presence); the
/// only legacy fallback is a missing `mode` on links printed before the token
/// existed, which default to `.ssh` here at the boundary.
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
        switch value("mode")?.lowercased() {
        case "direct":
            return .direct(
                name: name,
                baseURL: "http://\(host):\(agentPort)",
                remotePort: agentPort
            )
        case "ssh", nil:
            // `nil`: legacy links (pre-mode token) are SSH-shaped.
            return .ssh(
                name: name,
                sshUser: components.user ?? "",
                sshHost: host,
                sshPort: sshPort,
                remotePort: agentPort
            )
        default:
            // Unknown mode token: refuse to guess a kind from the URL shape.
            return nil
        }
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
