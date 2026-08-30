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
    /// Where the agent writes this profile's log, when it has one. Absent for
    /// rows that never log (discovery/claim rows with no launch claim).
    public let logPath: String?
    /// Status origin, parsed once at the decode boundary from the wire
    /// `source` string. Claim-ness has exactly one owner; it is never
    /// re-derived from profile names or runtime tags.
    public let origin: Origin
    /// Absolute/expanded paths the agent could not find (may be empty).
    public let missingArtifacts: [String]?

    public var id: String { profile }

    /// The four legal combinations of the wire `running`/`ready` booleans,
    /// named so display code switches once instead of re-deriving ad hoc.
    public enum Lifecycle: Equatable, Sendable {
        case stopped        // !running && !ready
        case starting       // running && !ready  - owned process, endpoint pending
        case running        // running && ready
        case readyUnowned   // !running && ready  - foreign listener answers health

        public var isActive: Bool { self != .stopped }
        public var isRunning: Bool { self == .running }
    }

    public var lifecycle: Lifecycle {
        switch (running, ready) {
        case (true, true): return .running
        case (true, false): return .starting
        case (false, true): return .readyUnowned
        case (false, false): return .stopped
        }
    }

    /// Typed origin. Wire values map 1:1; anything unrecognized (or absent)
    /// becomes `.unknown`. `listening` is the legacy wire value for discovery
    /// rows and stays folded into the synthetic-discovery census.
    public enum Origin: String, Equatable, Sendable {
        case profile
        case claim
        case discovery
        case listening
        case unknown

        public init(wireValue: String?) {
            self = wireValue.flatMap(Origin.init(rawValue:)) ?? .unknown
        }
    }

    /// Single owner of launch-folder claim-ness: the wire `source` field.
    /// Name prefixes (`port-`) and runtime tags are data, not identity.
    public var isLaunchFolderClaim: Bool { origin == .claim }

    /// Launchable when the agent found all model artifacts (missing_artifacts
    /// empty or absent) or the endpoint is live. Derived here from the wire
    /// facts - the Python agent's `launchable` field was deleted (L08): the
    /// two encodings were provably identical and one owner is enough.
    public var isLaunchable: Bool {
        (missingArtifacts?.isEmpty ?? true) || running || ready
    }

    /// Board rows: hide stale flat configs unless the endpoint is still live.
    /// Launch-folder / port claims stay visible so operators can see runners
    /// whose weights are temporarily missing.
    public var isBoardVisible: Bool {
        if !isLaunchable {
            if isLaunchFolderClaim {
                return true
            }
            return lifecycle.isActive
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
        logPath: String? = nil,
        origin: Origin = .unknown,
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
        self.origin = origin
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
        case origin = "source"
        case missingArtifacts = "missing_artifacts"
    }

    /// Parse at the boundary: `log_path` absent/null decodes to nil (no
    /// invented `""`), `source` becomes the typed origin (unknown stays
    /// unknown, never guessed).
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
        logPath = try container.decodeIfPresent(String.self, forKey: .logPath)
        origin = Origin(wireValue: try container.decodeIfPresent(String.self, forKey: .origin))
        missingArtifacts = try container.decodeIfPresent([String].self, forKey: .missingArtifacts)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeIfPresent(runtimeLabel, forKey: .runtimeLabel)
        try container.encodeIfPresent(runtimeTags, forKey: .runtimeTags)
        try container.encodeIfPresent(launchMode, forKey: .launchMode)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(requestModel, forKey: .requestModel)
        try container.encode(serverModelID, forKey: .serverModelID)
        try container.encodeIfPresent(pid, forKey: .pid)
        try container.encode(running, forKey: .running)
        try container.encode(ready, forKey: .ready)
        try container.encode(serverIDs, forKey: .serverIDs)
        try container.encodeIfPresent(rssMB, forKey: .rssMB)
        try container.encodeIfPresent(vramMB, forKey: .vramMB)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(logPath, forKey: .logPath)
        // Unknown origin is omitted - the local controller never had a source.
        if origin != .unknown {
            try container.encode(origin.rawValue, forKey: .origin)
        }
        try container.encodeIfPresent(missingArtifacts, forKey: .missingArtifacts)
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
            origin: origin,
            missingArtifacts: missingArtifacts
        )
    }

    var stateLabel: String {
        lifecycle.isRunning ? "Running" : "Not Running"
    }

    var stateDescription: String {
        var parts: [String] = [runtimeLabel ?? runtime, stateLabel]
        switch lifecycle {
        case .starting:
            parts.append("endpoint pending")
        case .running, .readyUnowned:
            parts.append("endpoint healthy")
        case .stopped:
            break
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
