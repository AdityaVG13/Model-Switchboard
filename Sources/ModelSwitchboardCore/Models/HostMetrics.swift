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

    public init(
        host: String? = nil,
        collectedAt: String? = nil,
        cpuPercent: Double? = nil,
        memory: HostMemoryMetrics? = nil,
        gpus: [HostGPUMetrics] = [],
        gpuSource: GPUSource? = nil,
        processes: [HostGPUProcess] = [],
        agentVersion: String? = nil
    ) {
        self.host = host
        self.collectedAt = collectedAt
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.gpus = gpus
        self.gpuSource = gpuSource
        self.processes = processes
        self.agentVersion = agentVersion
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

    public init(pid: Int? = nil, vramMB: Double? = nil) {
        self.pid = pid
        self.vramMB = vramMB
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case vramMB = "vram_mb"
    }
}
