import Foundation

extension DoctorReport {
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

    /// Derived from `findings` - a P0/P1 finding means unhealthy. This is the
    /// single owner; `healthy` is never carried on the wire (L27), so the
    /// report cannot claim healthy while a blocker finding exists.
    public var healthy: Bool {
        !(findings ?? []).contains { $0.severity.isBlocker }
    }
}
