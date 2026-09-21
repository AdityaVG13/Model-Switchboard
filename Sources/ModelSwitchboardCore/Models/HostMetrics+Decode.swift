import Foundation

extension HostMetricsPayload {
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
