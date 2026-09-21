import Foundation

public struct ControllerActionResponse: Codable, Equatable, Sendable {
    public let statuses: [ModelProfileStatus]?
    public let benchmark: BenchmarkStatus?
    public let integrations: [ControllerIntegration]?
    public let profilesDirectory: String?
    public let controllerRoot: String?
    public let error: String?

    public init(
        statuses: [ModelProfileStatus]?,
        benchmark: BenchmarkStatus?,
        integrations: [ControllerIntegration]?,
        profilesDirectory: String?,
        controllerRoot: String?,
        error: String?
    ) {
        self.statuses = statuses
        self.benchmark = benchmark
        self.integrations = integrations
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case statuses
        case benchmark
        case integrations
        case profilesDirectory = "profiles_dir"
        case controllerRoot = "controller_root"
        case error
    }
}

extension ControllerActionResponse: ControllerSourcePathProviding {}
