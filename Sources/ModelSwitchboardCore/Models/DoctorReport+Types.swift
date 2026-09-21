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
