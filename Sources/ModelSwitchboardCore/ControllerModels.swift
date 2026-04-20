import Foundation

public struct ControllerIntegration: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: String
    public let capabilities: [String]
    public let syncLabel: String?
    public let description: String?

    public init(
        id: String,
        displayName: String,
        kind: String,
        capabilities: [String],
        syncLabel: String?,
        description: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.capabilities = capabilities
        self.syncLabel = syncLabel
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case kind
        case capabilities
        case syncLabel = "sync_label"
        case description
    }
}

public struct ModelProfileStatus: Codable, Identifiable, Equatable, Sendable {
    public let profile: String
    public let displayName: String
    public let runtime: String
    public let host: String
    public let port: String
    public let baseURL: String
    public let requestModel: String
    public let serverModelID: String
    public let pid: Int?
    public let running: Bool
    public let ready: Bool
    public let serverIDs: [String]
    public let rssMB: Double?
    public let command: String?
    public let logPath: String

    public var id: String { profile }

    public init(
        profile: String,
        displayName: String,
        runtime: String,
        host: String,
        port: String,
        baseURL: String,
        requestModel: String,
        serverModelID: String,
        pid: Int?,
        running: Bool,
        ready: Bool,
        serverIDs: [String],
        rssMB: Double?,
        command: String?,
        logPath: String
    ) {
        self.profile = profile
        self.displayName = displayName
        self.runtime = runtime
        self.host = host
        self.port = port
        self.baseURL = baseURL
        self.requestModel = requestModel
        self.serverModelID = serverModelID
        self.pid = pid
        self.running = running
        self.ready = ready
        self.serverIDs = serverIDs
        self.rssMB = rssMB
        self.command = command
        self.logPath = logPath
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case displayName = "display_name"
        case runtime
        case host
        case port
        case baseURL = "base_url"
        case requestModel = "request_model"
        case serverModelID = "server_model_id"
        case pid
        case running
        case ready
        case serverIDs = "server_ids"
        case rssMB = "rss_mb"
        case command
        case logPath = "log_path"
    }
}

public struct BenchmarkLatestRow: Codable, Equatable, Sendable {
    public let profile: String?
    public let runtime: String?
    public let ttftMS: Double?
    public let decodeTokensPerSec: Double?
    public let e2eTokensPerSec: Double?
    public let rssMB: Double?

    public init(
        profile: String?,
        runtime: String?,
        ttftMS: Double?,
        decodeTokensPerSec: Double?,
        e2eTokensPerSec: Double?,
        rssMB: Double?
    ) {
        self.profile = profile
        self.runtime = runtime
        self.ttftMS = ttftMS
        self.decodeTokensPerSec = decodeTokensPerSec
        self.e2eTokensPerSec = e2eTokensPerSec
        self.rssMB = rssMB
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case runtime
        case ttftMS = "ttft_ms"
        case decodeTokensPerSec = "decode_tokens_per_sec"
        case e2eTokensPerSec = "e2e_tokens_per_sec"
        case rssMB = "rss_mb"
    }
}

public struct BenchmarkLatestReport: Codable, Equatable, Sendable {
    public let generatedAt: String?
    public let suite: String?
    public let profiles: [String]
    public let rows: [BenchmarkLatestRow]
    public let jsonPath: String?
    public let markdownPath: String?

    public init(
        generatedAt: String?,
        suite: String?,
        profiles: [String],
        rows: [BenchmarkLatestRow],
        jsonPath: String?,
        markdownPath: String?
    ) {
        self.generatedAt = generatedAt
        self.suite = suite
        self.profiles = profiles
        self.rows = rows
        self.jsonPath = jsonPath
        self.markdownPath = markdownPath
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case suite
        case profiles
        case rows
        case jsonPath = "json_path"
        case markdownPath = "markdown_path"
    }
}

public struct BenchmarkStatus: Codable, Equatable, Sendable {
    public let running: Bool
    public let pid: Int?
    public let logPath: String?
    public let latest: BenchmarkLatestReport?

    public init(running: Bool, pid: Int?, logPath: String?, latest: BenchmarkLatestReport?) {
        self.running = running
        self.pid = pid
        self.logPath = logPath
        self.latest = latest
    }

    enum CodingKeys: String, CodingKey {
        case running
        case pid
        case logPath = "log_path"
        case latest
    }
}

public struct ProfileDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public let profile: String
    public let displayName: String
    public let runtime: String
    public let errors: [String]
    public let warnings: [String]
    public let running: Bool
    public let ready: Bool
    public let pid: Int?
    public let baseURL: String

    public var id: String { profile }

    public init(
        profile: String,
        displayName: String,
        runtime: String,
        errors: [String],
        warnings: [String],
        running: Bool,
        ready: Bool,
        pid: Int?,
        baseURL: String
    ) {
        self.profile = profile
        self.displayName = displayName
        self.runtime = runtime
        self.errors = errors
        self.warnings = warnings
        self.running = running
        self.ready = ready
        self.pid = pid
        self.baseURL = baseURL
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case displayName = "display_name"
        case runtime
        case errors
        case warnings
        case running
        case ready
        case pid
        case baseURL = "base_url"
    }
}

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

public extension ModelProfileStatus {
    func updating(
        pid: Int? = nil,
        running: Bool? = nil,
        ready: Bool? = nil,
        serverIDs: [String]? = nil,
        rssMB: Double? = nil
    ) -> Self {
        Self(
            profile: profile,
            displayName: displayName,
            runtime: runtime,
            host: host,
            port: port,
            baseURL: baseURL,
            requestModel: requestModel,
            serverModelID: serverModelID,
            pid: pid ?? self.pid,
            running: running ?? self.running,
            ready: ready ?? self.ready,
            serverIDs: serverIDs ?? self.serverIDs,
            rssMB: rssMB ?? self.rssMB,
            command: command,
            logPath: logPath
        )
    }

    var stateLabel: String {
        if running { return "Running" }
        return "Not Running"
    }

    var stateDescription: String {
        var parts: [String] = [runtime, stateLabel]
        if running && !ready {
            parts.append("endpoint pending")
        } else if ready {
            parts.append("endpoint healthy")
        }
        if let rssMB {
            parts.append(String(format: "%.1f MB", rssMB))
        }
        return parts.joined(separator: " • ")
    }
}
