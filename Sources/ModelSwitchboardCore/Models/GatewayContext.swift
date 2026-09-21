import Foundation

/// The identity a `SwitchboardStore` runs under.
public struct GatewayContext: Equatable, Sendable {
    public let id: String
    public let name: String
    public var isLocal: Bool { id == Self.localID }

    public static let localID = "local"

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let local = GatewayContext(id: localID, name: "This Mac")

    public init(config: GatewayConfig) {
        self.init(id: config.id, name: config.name)
    }
}
