import Foundation

/// Where the agent's GPU metrics came from, parsed once at the decode
/// boundary. Wire strings are the raw values ("nvidia-smi" / "unavailable");
/// anything unrecognized decodes to `.unknown` instead of failing the payload
/// (L28).
public enum GPUSource: String, Equatable, Sendable {
    case nvidiaSmi = "nvidia-smi"
    case unavailable = "unavailable"
    case unknown = "unknown"

    public init(wireValue: String?) {
        self = wireValue.flatMap(GPUSource.init(rawValue:)) ?? .unknown
    }
}

extension GPUSource: Codable {
    public init(from decoder: Decoder) throws {
        self = GPUSource(wireValue: try? decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
