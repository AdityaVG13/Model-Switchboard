import Foundation

/// Where the agent's GPU metrics came from, parsed once at the decode
/// boundary. Wire strings are the raw values ("nvidia-smi" / "unavailable");
/// anything unrecognized decodes to `.unknown` instead of failing the payload
/// (L28).
public enum GPUSource: String, Equatable, Sendable {
    case nvidiaSmi = "nvidia-smi"
    case unavailable = "unavailable"
    case unknown = "unknown"

    public init(wireValue: String?) {
        self = wireValue.flatMap(GPUSource.init(rawValue:)) ?? .unknown
    }
}

extension GPUSource: Codable {
    public init(from decoder: Decoder) throws {
        self = GPUSource(wireValue: try? decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Live host stats from a remote agent (`GET /api/host/metrics`).
///
/// Units (documented for UI):
/// - `cpuPercent` / GPU `utilPercent`: 0…100
/// - `tempC`: Celsius
/// - memory / VRAM fields: megabytes (MiB from nvidia-smi; MB from /proc)
public struct HostMetricsPayload: Codable, Equatable, Sendable {
    public let host: String?
    public let collectedAt: String?
    public let cpuPercent: Double?
    public let memory: HostMemoryMetrics?
    public let gpus: [HostGPUMetrics]
    public let gpuSource: GPUSource?
    public let processes: [HostGPUProcess]
    public let agentVersion: String?
    public let uptimeSeconds: Double?
    public let storage: HostStorageMetrics?
    public let network: HostNetworkMetrics?
    public let tailscale: TailnetHealth?

    public init(
        host: String? = nil,
        collectedAt: String? = nil,
        cpuPercent: Double? = nil,
        memory: HostMemoryMetrics? = nil,
        gpus: [HostGPUMetrics] = [],
        gpuSource: GPUSource? = nil,
        processes: [HostGPUProcess] = [],
        agentVersion: String? = nil,
        uptimeSeconds: Double? = nil,
        storage: HostStorageMetrics? = nil,
        network: HostNetworkMetrics? = nil,
        tailscale: TailnetHealth? = nil
    ) {
        self.host = host
        self.collectedAt = collectedAt
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.gpus = gpus
        self.gpuSource = gpuSource
        self.processes = processes
        self.agentVersion = agentVersion
        self.uptimeSeconds = uptimeSeconds
        self.storage = storage
        self.network = network
        self.tailscale = tailscale
    }

    enum CodingKeys: String, CodingKey {
        case host
        case collectedAt = "collected_at"
        case cpuPercent = "cpu_percent"
        case memory
        case gpus
        case gpuSource = "gpu_source"
        case processes
        case agentVersion = "agent_version"
        case uptimeSeconds = "uptime_seconds"
        case storage
        case network
        case tailscale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        collectedAt = try container.decodeIfPresent(String.self, forKey: .collectedAt)
        cpuPercent = try container.decodeIfPresent(Double.self, forKey: .cpuPercent)
        memory = try container.decodeIfPresent(HostMemoryMetrics.self, forKey: .memory)
        gpus = try container.decodeIfPresent([HostGPUMetrics].self, forKey: .gpus) ?? []
        gpuSource = try container.decodeIfPresent(GPUSource.self, forKey: .gpuSource)
        processes = try container.decodeIfPresent([HostGPUProcess].self, forKey: .processes) ?? []
        agentVersion = try container.decodeIfPresent(String.self, forKey: .agentVersion)
        uptimeSeconds = try container.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
        storage = try container.decodeIfPresent(HostStorageMetrics.self, forKey: .storage)
        network = try container.decodeIfPresent(HostNetworkMetrics.self, forKey: .network)
        tailscale = try container.decodeIfPresent(TailnetHealth.self, forKey: .tailscale)
    }
}

public struct HostStorageMetrics: Codable, Equatable, Sendable {
    public let usedMB: Double?
    public let totalMB: Double?
    public let percent: Double?
    public let source: String?

    public init(usedMB: Double? = nil, totalMB: Double? = nil, percent: Double? = nil, source: String? = nil) {
        self.usedMB = usedMB
        self.totalMB = totalMB
        self.percent = percent
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case usedMB = "used_mb"
        case totalMB = "total_mb"
        case percent
        case source
    }
}

public struct HostNetworkMetrics: Codable, Equatable, Sendable {
    public let rxKbps: Double?
    public let txKbps: Double?
    public let source: String?

    public init(rxKbps: Double? = nil, txKbps: Double? = nil, source: String? = nil) {
        self.rxKbps = rxKbps
        self.txKbps = txKbps
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case rxKbps = "rx_kbps"
        case txKbps = "tx_kbps"
        case source
    }
}

/// The host's own view of its tailnet membership (Self.Online + warnings).
/// Peer state is never the verdict.
public struct TailnetHealth: Codable, Equatable, Sendable {
    public let online: Bool?
    public let backendState: String?
    public let ipv4: String?
    public let dnsName: String?
    public let health: [String]

    public init(
        online: Bool? = nil,
        backendState: String? = nil,
        ipv4: String? = nil,
        dnsName: String? = nil,
        health: [String] = []
    ) {
        self.online = online
        self.backendState = backendState
        self.ipv4 = ipv4
        self.dnsName = dnsName
        self.health = health
    }

    enum CodingKeys: String, CodingKey {
        case online
        case backendState = "backend_state"
        case ipv4
        case dnsName = "dns_name"
        case health
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        online = try container.decodeIfPresent(Bool.self, forKey: .online)
        backendState = try container.decodeIfPresent(String.self, forKey: .backendState)
        ipv4 = try container.decodeIfPresent(String.self, forKey: .ipv4)
        dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
        health = try container.decodeIfPresent([String].self, forKey: .health) ?? []
    }
}

public struct HostMemoryMetrics: Codable, Equatable, Sendable {
    public let usedMB: Double?
    public let totalMB: Double?
    public let percent: Double?
    public let source: String?

    public init(usedMB: Double? = nil, totalMB: Double? = nil, percent: Double? = nil, source: String? = nil) {
        self.usedMB = usedMB
        self.totalMB = totalMB
        self.percent = percent
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case usedMB = "used_mb"
        case totalMB = "total_mb"
        case percent
        case source
    }
}

public struct HostGPUMetrics: Codable, Equatable, Identifiable, Sendable {
    public let index: Int?
    public let name: String?
    public let utilPercent: Double?
    public let tempC: Double?
    public let vramUsedMB: Double?
    public let vramTotalMB: Double?

    /// Stable identity for chart/row continuity: the nvidia-smi index when
    /// present, else the GPU name, else a fixed fallback. The former
    /// `name?.hashValue` id was unstable across launches (Swift String hashing
    /// is randomized per process), so identical rows could change identity
    /// between polls (L28).
    public var id: String {
        if let index { return "gpu-\(index)" }
        if let name { return name }
        return "gpu-unknown"
    }

    public init(
        index: Int? = nil,
        name: String? = nil,
        utilPercent: Double? = nil,
        tempC: Double? = nil,
        vramUsedMB: Double? = nil,
        vramTotalMB: Double? = nil
    ) {
        self.index = index
        self.name = name
        self.utilPercent = utilPercent
        self.tempC = tempC
        self.vramUsedMB = vramUsedMB
        self.vramTotalMB = vramTotalMB
    }

    enum CodingKeys: String, CodingKey {
        case index
        case name
        case utilPercent = "util_percent"
        case tempC = "temp_c"
        case vramUsedMB = "vram_used_mb"
        case vramTotalMB = "vram_total_mb"
    }
}

public struct HostGPUProcess: Codable, Equatable, Sendable {
    public let pid: Int?
    public let vramMB: Double?
    public let name: String?

    public init(pid: Int? = nil, vramMB: Double? = nil, name: String? = nil) {
        self.pid = pid
        self.vramMB = vramMB
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case vramMB = "vram_mb"
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        vramMB = try container.decodeIfPresent(Double.self, forKey: .vramMB)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

/// Live serving rates decoded from the agent's status row `serving` object.
/// All fields optional: old agents omit `serving` entirely, and even current
/// agents report nulls when the backend probe fails.
public struct ServingMetrics: Codable, Equatable, Sendable {
    public let backend: String?
    public let tokS: Double?
    public let promptTokS: Double?
    public let kvCacheUsage: Double?
    public let requestsRunning: Double?
    public let requestsWaiting: Double?

    public init(
        backend: String? = nil,
        tokS: Double? = nil,
        promptTokS: Double? = nil,
        kvCacheUsage: Double? = nil,
        requestsRunning: Double? = nil,
        requestsWaiting: Double? = nil
    ) {
        self.backend = backend
        self.tokS = tokS
        self.promptTokS = promptTokS
        self.kvCacheUsage = kvCacheUsage
        self.requestsRunning = requestsRunning
        self.requestsWaiting = requestsWaiting
    }

    enum CodingKeys: String, CodingKey {
        case backend
        case tokS = "tok_s"
        case promptTokS = "prompt_tok_s"
        case kvCacheUsage = "kv_cache_usage"
        case requestsRunning = "requests_running"
        case requestsWaiting = "requests_waiting"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backend = try container.decodeIfPresent(String.self, forKey: .backend)
        tokS = try container.decodeIfPresent(Double.self, forKey: .tokS)
        promptTokS = try container.decodeIfPresent(Double.self, forKey: .promptTokS)
        kvCacheUsage = try container.decodeIfPresent(Double.self, forKey: .kvCacheUsage)
        requestsRunning = try container.decodeIfPresent(Double.self, forKey: .requestsRunning)
        requestsWaiting = try container.decodeIfPresent(Double.self, forKey: .requestsWaiting)
    }
}
