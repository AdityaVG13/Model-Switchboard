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
/// settings form). The other kind's fields cannot be represented - a `.direct`
/// gateway can never carry an ssh host and an `.ssh` gateway can never carry a
/// base URL - so the old open product (`.direct` + `sshHost` set, kind
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

    /// Private-by-convention construction: callers use the `direct`/`ssh`
    /// factories, which set exactly the fields their kind may carry.
    init(id: String, name: String, enabled: Bool, connection: Connection) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.connection = connection
    }
}
