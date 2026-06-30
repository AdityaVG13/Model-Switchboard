import Foundation

public struct ControllerSourcePaths: Equatable, Sendable {
    public let profilesDirectory: String?
    public let controllerRoot: String?

    public init(profilesDirectory: String?, controllerRoot: String?) {
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
    }
}

public protocol ControllerSourcePathProviding {
    var profilesDirectory: String? { get }
    var controllerRoot: String? { get }
}

public extension ControllerSourcePathProviding {
    var sourcePaths: ControllerSourcePaths {
        ControllerSourcePaths(
            profilesDirectory: profilesDirectory,
            controllerRoot: controllerRoot
        )
    }
}

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

public struct ControllerActionResponse: Codable, Equatable, Sendable {
    public let ok: Bool?
    public let statuses: [ModelProfileStatus]?
    public let benchmark: BenchmarkStatus?
    public let integrations: [ControllerIntegration]?
    public let profilesDirectory: String?
    public let controllerRoot: String?
    public let error: String?

    public init(
        ok: Bool?,
        statuses: [ModelProfileStatus]?,
        benchmark: BenchmarkStatus?,
        integrations: [ControllerIntegration]?,
        profilesDirectory: String?,
        controllerRoot: String?,
        error: String?
    ) {
        self.ok = ok
        self.statuses = statuses
        self.benchmark = benchmark
        self.integrations = integrations
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case statuses
        case benchmark
        case integrations
        case profilesDirectory = "profiles_dir"
        case controllerRoot = "controller_root"
        case error
    }
}

extension ControllerStatusPayload: ControllerSourcePathProviding {}
extension ControllerActionResponse: ControllerSourcePathProviding {}

public struct DashboardSummary: Equatable, Sendable {
    public let totalProfiles: Int
    public let runningProfiles: Int
    public let readyProfiles: Int
    public let benchmarkRunning: Bool
    public let benchmarkSuite: String?

    public init(payload: ControllerStatusPayload) {
        totalProfiles = payload.statuses.count
        runningProfiles = payload.statuses.filter(\.running).count
        readyProfiles = payload.statuses.filter(\.ready).count
        benchmarkRunning = payload.benchmark?.running ?? false
        benchmarkSuite = payload.benchmark?.latest?.suite
    }

    public var menuBarTitle: String {
        if benchmarkRunning {
            return "Bench \(readyProfiles)/\(totalProfiles)"
        }
        return "Ready \(readyProfiles)/\(totalProfiles)"
    }

    public var menuBarSystemImage: String {
        if benchmarkRunning {
            return "speedometer"
        }
        if readyProfiles > 0 {
            return "memorychip.fill"
        }
        if runningProfiles > 0 {
            return "memorychip"
        }
        return "cpu"
    }
}
