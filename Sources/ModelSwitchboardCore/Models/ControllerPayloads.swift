import Foundation

public struct ControllerStatusPayload: Codable, Equatable, Sendable {
    public let statuses: [ModelProfileStatus]
    public let benchmark: BenchmarkStatus?
    public let integrations: [ControllerIntegration]
    public let profilesDirectory: String?
    public let controllerRoot: String?

    public init(
        statuses: [ModelProfileStatus],
        benchmark: BenchmarkStatus?,
        integrations: [ControllerIntegration] = [],
        profilesDirectory: String? = nil,
        controllerRoot: String? = nil
    ) {
        self.statuses = statuses
        self.benchmark = benchmark
        self.integrations = integrations
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
    }

    enum CodingKeys: String, CodingKey {
        case statuses
        case benchmark
        case integrations
        case profilesDirectory = "profiles_dir"
        case controllerRoot = "controller_root"
    }
}

extension ControllerStatusPayload: ControllerSourcePathProviding {}
