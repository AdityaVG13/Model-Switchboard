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

public struct DoctorFinding: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let severity: String
    public let subsystem: String
    public let message: String
    public let evidence: String?
    public let remediation: String?
    public let autoFixable: Bool?
    public let fixer: String?

    public init(
        id: String,
        severity: String,
        subsystem: String,
        message: String,
        evidence: String? = nil,
        remediation: String? = nil,
        autoFixable: Bool? = nil,
        fixer: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.subsystem = subsystem
        self.message = message
        self.evidence = evidence
        self.remediation = remediation
        self.autoFixable = autoFixable
        self.fixer = fixer
    }

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case subsystem
        case message
        case evidence
        case remediation
        case autoFixable = "auto_fixable"
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
    public let healthy: Bool?
    public let findings: [DoctorFinding]?
    public let nextSteps: [String]?

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
        healthy: Bool? = nil,
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
        self.healthy = healthy
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
        case healthy
        case findings
        case nextSteps = "next_steps"
    }
}
