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
    /// GPU memory in MB when the agent can attribute VRAM to this process (nvidia-smi).
    public let vramMB: Double?
    public let command: String?
    public let logPath: String
    /// Status origin: profile, claim, or discovery.
    public let source: String?
    /// False when configured model weights/dirs are missing on the agent host.
    public let launchable: Bool?
    /// Absolute/expanded paths the agent could not find (may be empty).
    public let missingArtifacts: [String]?

    public var id: String { profile }

    /// Board rows: hide stale configs unless the endpoint is still live.
    public var isBoardVisible: Bool {
        if launchable == false {
            return running || ready
        }
        return true
    }

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
        vramMB: Double? = nil,
        command: String?,
        logPath: String,
        source: String? = nil,
        launchable: Bool? = nil,
        missingArtifacts: [String]? = nil
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
        self.vramMB = vramMB
        self.command = command
        self.logPath = logPath
        self.source = source
        self.launchable = launchable
        self.missingArtifacts = missingArtifacts
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
        case vramMB = "vram_mb"
        case command
        case logPath = "log_path"
        case source
        case launchable
        case missingArtifacts = "missing_artifacts"
    }

    /// Tolerant decode: remote agents may omit or null `log_path` (discovery rows).
    /// Never fail the whole gateway status payload for a cosmetic field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(String.self, forKey: .profile)
        displayName = try container.decode(String.self, forKey: .displayName)
        runtime = try container.decode(String.self, forKey: .runtime)
        runtimeLabel = try container.decodeIfPresent(String.self, forKey: .runtimeLabel)
        runtimeTags = try container.decodeIfPresent([String].self, forKey: .runtimeTags)
        launchMode = try container.decodeIfPresent(String.self, forKey: .launchMode)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(String.self, forKey: .port)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        requestModel = try container.decode(String.self, forKey: .requestModel)
        serverModelID = try container.decode(String.self, forKey: .serverModelID)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        running = try container.decode(Bool.self, forKey: .running)
        ready = try container.decode(Bool.self, forKey: .ready)
        serverIDs = try container.decodeIfPresent([String].self, forKey: .serverIDs) ?? []
        rssMB = try container.decodeIfPresent(Double.self, forKey: .rssMB)
        vramMB = try container.decodeIfPresent(Double.self, forKey: .vramMB)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        if let path = try container.decodeIfPresent(String.self, forKey: .logPath) {
            logPath = path
        } else {
            logPath = ""
        }
        source = try container.decodeIfPresent(String.self, forKey: .source)
        launchable = try container.decodeIfPresent(Bool.self, forKey: .launchable)
        missingArtifacts = try container.decodeIfPresent([String].self, forKey: .missingArtifacts)
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
        rssMB: Double? = nil,
        vramMB: Double? = nil
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
            vramMB: vramMB ?? self.vramMB,
            command: command,
            logPath: logPath,
            source: source,
            launchable: launchable,
            missingArtifacts: missingArtifacts
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
        if let vramMB {
            parts.append(String(format: "%.1f MB VRAM", vramMB))
        } else if let rssMB {
            parts.append(String(format: "%.1f MB RSS", rssMB))
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

extension ModelProfileStatus {
    public var usesLoopbackEndpoint: Bool {
        LoopbackHost.isLoopbackURL(baseURL, fallbackHost: host)
    }
}
