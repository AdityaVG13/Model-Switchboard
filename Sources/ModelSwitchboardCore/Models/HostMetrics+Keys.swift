import Foundation

extension HostMetricsPayload {
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
}
