import Foundation

public struct ControllerHeartbeat: Codable, Equatable, Sendable {
    public let url: String
    public let reachable: Bool
    public let profiles: Int
    public let integrations: Int

    public init(url: String, reachable: Bool, profiles: Int, integrations: Int) {
        self.url = url
        self.reachable = reachable
        self.profiles = profiles
        self.integrations = integrations
    }
}

public struct LaunchAgentStatus: Codable, Equatable, Sendable {
    public let plistPath: String
    public let installed: Bool
    public let running: Bool

    public init(plistPath: String, installed: Bool, running: Bool) {
        self.plistPath = plistPath
        self.installed = installed
        self.running = running
    }

    enum CodingKeys: String, CodingKey {
        case plistPath = "plist_path"
        case installed
        case running
    }
}

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

public struct DoctorReport: Codable, Equatable, Sendable {
    public let controller: ControllerHeartbeat
    public let launchAgent: LaunchAgentStatus
    public let integrations: [ControllerIntegration]
    public let profilesDirectory: String?
    public let controllerRoot: String?
    public let profiles: [ProfileDiagnostic]
    public let schemaVersion: String?
    public let doctorContractVersion: String?
    public let toolVersion: String?
    public let generatedAt: String?
    public let findings: [DoctorFinding]?
    public let nextSteps: [String]?

    /// Derived from `findings` - a P0/P1 finding means unhealthy. This is the
    /// single owner; `healthy` is never carried on the wire (L27), so the
    /// report cannot claim healthy while a blocker finding exists.
    public var healthy: Bool {
        !(findings ?? []).contains { $0.severity.isBlocker }
    }

    public init(
        controller: ControllerHeartbeat,
        launchAgent: LaunchAgentStatus,
        integrations: [ControllerIntegration],
        profilesDirectory: String?,
        controllerRoot: String?,
        profiles: [ProfileDiagnostic],
        schemaVersion: String? = nil,
        doctorContractVersion: String? = nil,
        toolVersion: String? = nil,
        generatedAt: String? = nil,
        findings: [DoctorFinding]? = nil,
        nextSteps: [String]? = nil
    ) {
        self.controller = controller
        self.launchAgent = launchAgent
        self.integrations = integrations
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
        self.profiles = profiles
        self.schemaVersion = schemaVersion
        self.doctorContractVersion = doctorContractVersion
        self.toolVersion = toolVersion
        self.generatedAt = generatedAt
        self.findings = findings
        self.nextSteps = nextSteps
    }

    enum CodingKeys: String, CodingKey {
        case controller
        case launchAgent = "launch_agent"
        case integrations
        case profilesDirectory = "profiles_dir"
        case controllerRoot = "controller_root"
        case profiles
        case schemaVersion = "schema_version"
        case doctorContractVersion = "doctor_contract_version"
        case toolVersion = "tool_version"
        case generatedAt = "generated_at"
        case findings
        case nextSteps = "next_steps"
    }
}
