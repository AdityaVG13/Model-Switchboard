import Foundation

public struct ModelProfileStatus: Codable, Identifiable, Equatable, Sendable {
    public let profile: String
    public let displayName: String
    public let runtime: String
    public let runtimeLabel: String?
    public let runtimeTags: [String]?
    public let launchMode: String?
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
        runtimeLabel: String? = nil,
        runtimeTags: [String]? = nil,
        launchMode: String? = nil,
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
        self.runtimeLabel = runtimeLabel
        self.runtimeTags = runtimeTags
        self.launchMode = launchMode
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
        case runtimeLabel = "runtime_label"
        case runtimeTags = "runtime_tags"
        case launchMode = "launch_mode"
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

public extension ModelProfileStatus {
    static func compareForDisplay(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.running != rhs.running {
            return lhs.running && !rhs.running
        }
        if lhs.running && lhs.ready != rhs.ready {
            return lhs.ready && !rhs.ready
        }

        let lhsHostRank = lhs.displayHostRank
        let rhsHostRank = rhs.displayHostRank
        if lhsHostRank != rhsHostRank {
            return lhsHostRank < rhsHostRank
        }

        let lhsHost = lhs.normalizedDisplayHost
        let rhsHost = rhs.normalizedDisplayHost
        if lhsHost != rhsHost {
            return lhsHost.localizedCaseInsensitiveCompare(rhsHost) == .orderedAscending
        }

        let lhsPort = lhs.displayPortRank
        let rhsPort = rhs.displayPortRank
        if lhsPort != rhsPort {
            return lhsPort < rhsPort
        }

        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.profile.localizedCaseInsensitiveCompare(rhs.profile) == .orderedAscending
    }

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
            runtimeLabel: runtimeLabel,
            runtimeTags: runtimeTags,
            launchMode: launchMode,
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
        var parts: [String] = [runtimeLabel ?? runtime, stateLabel]
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

    private var displayHostRank: Int {
        isLoopbackHost ? 0 : 1
    }

    private var normalizedDisplayHost: String {
        if isLoopbackHost {
            return "localhost"
        }
        return host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayPortRank: Int {
        Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .max
    }

    private var isLoopbackHost: Bool {
        LoopbackHost.isLoopback(host)
    }
}
