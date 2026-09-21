import Foundation

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
}
