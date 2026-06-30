import Foundation

public struct ControllerIntegration: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: String
    public let capabilities: [String]
    public let syncLabel: String?
    public let description: String?

    public init(
        id: String,
        displayName: String,
        kind: String,
        capabilities: [String],
        syncLabel: String?,
        description: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.capabilities = capabilities
        self.syncLabel = syncLabel
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case kind
        case capabilities
        case syncLabel = "sync_label"
        case description
    }
}
