import Foundation

/// The host's own view of its tailnet membership (Self.Online + warnings).
/// Peer state is never the verdict.
public struct TailnetHealth: Codable, Equatable, Sendable {
    public let online: Bool?
    public let backendState: String?
    public let ipv4: String?
    public let dnsName: String?
    public let health: [String]

    public init(
        online: Bool? = nil,
        backendState: String? = nil,
        ipv4: String? = nil,
        dnsName: String? = nil,
        health: [String] = []
    ) {
        self.online = online
        self.backendState = backendState
        self.ipv4 = ipv4
        self.dnsName = dnsName
        self.health = health
    }

    enum CodingKeys: String, CodingKey {
        case online
        case backendState = "backend_state"
        case ipv4
        case dnsName = "dns_name"
        case health
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        online = try container.decodeIfPresent(Bool.self, forKey: .online)
        backendState = try container.decodeIfPresent(String.self, forKey: .backendState)
        ipv4 = try container.decodeIfPresent(String.self, forKey: .ipv4)
        dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
        health = try container.decodeIfPresent([String].self, forKey: .health) ?? []
    }
}
