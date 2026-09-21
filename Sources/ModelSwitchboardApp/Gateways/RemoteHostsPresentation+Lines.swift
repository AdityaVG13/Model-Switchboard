import SwiftUI
import ModelSwitchboardCore

extension RemoteHostsPresentation {
    static func memoryDetail(_ memory: HostMemoryMetrics?) -> String? {
        guard let used = memory?.usedMB, let total = memory?.totalMB, total > 0 else { return nil }
        return String(format: "%.0f/%.0f GB", used / 1024, total / 1024)
    }

    static func gpuLine(_ gpu: HostGPUMetrics) -> String {
        var parts: [String] = []
        if let index = gpu.index { parts.append("GPU\(index)") }
        if let name = gpu.name { parts.append(name) }
        if let util = gpu.utilPercent { parts.append(String(format: "%.0f%%", util)) }
        if let temp = gpu.tempC { parts.append(String(format: "%.0f°C", temp)) }
        if let used = gpu.vramUsedMB, let total = gpu.vramTotalMB {
            parts.append(String(format: "%.1f/%.1f GB", used / 1024, total / 1024))
        }
        return parts.joined(separator: " · ")
    }

    static func gpuProcessName(for status: ModelProfileStatus, metrics: HostMetricsPayload?) -> String? {
        guard let pid = status.pid else { return nil }
        return metrics?.processes.first(where: { $0.pid == pid })?.name
    }
}
