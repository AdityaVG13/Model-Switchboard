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

public struct DoctorReport: Codable, Equatable, Sendable {
    public let controller: ControllerHeartbeat
    public let launchAgent: LaunchAgentStatus
    public let integrations: [ControllerIntegration]
    public let profilesDirectory: String?
    public let controllerRoot: String?
    public let profiles: [ProfileDiagnostic]

    public init(
        controller: ControllerHeartbeat,
        launchAgent: LaunchAgentStatus,
        integrations: [ControllerIntegration],
        profilesDirectory: String?,
        controllerRoot: String?,
        profiles: [ProfileDiagnostic]
    ) {
        self.controller = controller
        self.launchAgent = launchAgent
        self.integrations = integrations
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
        self.profiles = profiles
    }

    enum CodingKeys: String, CodingKey {
        case controller
        case launchAgent = "launch_agent"
        case integrations
        case profilesDirectory = "profiles_dir"
        case controllerRoot = "controller_root"
        case profiles
    }
}
