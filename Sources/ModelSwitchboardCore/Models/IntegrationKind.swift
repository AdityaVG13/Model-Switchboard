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
