import Foundation

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
}
