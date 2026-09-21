import Foundation

/// Severity of a doctor finding, parsed once at the decode boundary. Wire
/// strings are the raw values ("P0"…"P3"); anything unrecognized decodes to
/// `.unknown` instead of failing the whole report (L27).
public enum DoctorSeverity: String, Equatable, Sendable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    /// Unrecognized wire value, tolerated at decode. Never a blocker.
    case unknown = "unknown"

    /// P0/P1 findings block health; everything else (including `.unknown`)
    /// is non-blocking - matches the old string comparison semantics.
    public var isBlocker: Bool { self == .p0 || self == .p1 }

    public init(wireValue: String?) {
        self = wireValue.flatMap(DoctorSeverity.init(rawValue:)) ?? .unknown
    }
}

extension DoctorSeverity: Codable {
    public init(from decoder: Decoder) throws {
        self = DoctorSeverity(wireValue: try? decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
