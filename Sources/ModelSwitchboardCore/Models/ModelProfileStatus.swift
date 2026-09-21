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
    /// Live serving rates (tok/s etc.) for running rows; nil for old agents
    /// or when the backend probe fails.
    public let serving: ServingMetrics?

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
        vramMB: Double? = nil,
        command: String?,
        logPath: String? = nil,
        origin: Origin = .unknown,
        missingArtifacts: [String]? = [],
        serving: ServingMetrics? = nil
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
        self.serving = serving
    }
}
