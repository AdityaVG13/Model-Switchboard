import Foundation

/// Integration kind, parsed once at the decode boundary. Wire strings are
/// the raw values ("model_registry"); anything unrecognized decodes to
/// `.unknown` instead of failing the payload (L29).
public enum IntegrationKind: String, Equatable, Sendable {
    case modelRegistry = "model_registry"
    case unknown = "unknown"

    public init(wireValue: String?) {
        self = wireValue.flatMap(IntegrationKind.init(rawValue:)) ?? .unknown
    }
}

extension IntegrationKind: Codable {
    public init(from decoder: Decoder) throws {
        self = IntegrationKind(wireValue: try? decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ControllerIntegration: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: IntegrationKind
    public let capabilities: [String]
    public let syncLabel: String?
    public let description: String?

    public init(
        id: String,
        displayName: String,
        kind: IntegrationKind,
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
