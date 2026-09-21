import Foundation

public struct DoctorFinding: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let severity: DoctorSeverity
    public let subsystem: String
    public let message: String
    public let evidence: String?
    public let remediation: String?
    /// The fixer command that can auto-remediate this finding. A finding is
    /// auto-fixable iff it names a fixer: `autoFixable` is DERIVED, never
    /// stored, so `autoFixable == true` without a fixer (or a fixer that is
    /// not auto-fixable) is unrepresentable (L27).
    public let fixer: String?

    public var autoFixable: Bool { fixer != nil }

    public init(
        id: String,
        severity: DoctorSeverity,
        subsystem: String,
        message: String,
        evidence: String? = nil,
        remediation: String? = nil,
        fixer: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.subsystem = subsystem
        self.message = message
        self.evidence = evidence
        self.remediation = remediation
        self.fixer = fixer
    }

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case subsystem
        case message
        case evidence
        case remediation
        case fixer
    }
}
