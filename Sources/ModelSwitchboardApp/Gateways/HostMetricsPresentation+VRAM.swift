import Foundation
import ModelSwitchboardCore

extension HostMetricsPresentation {
    /// VRAM MiB for a process from host metrics compute-apps map.
    static func processVRAMMB(pid: Int?, metrics: HostMetricsPayload?) -> Double? {
        guard let pid, let metrics else { return nil }
        return metrics.processes.first(where: { $0.pid == pid })?.vramMB
    }

    /// Prefer status `vram_mb`, then host-metrics process map. Never RSS.
    static func effectiveProfileVRAMMB(
        status: ModelProfileStatus,
        metrics: HostMetricsPayload?
    ) -> Double? {
        if let vram = status.vramMB { return vram }
        return processVRAMMB(pid: status.pid, metrics: metrics)
    }

    /// Host-level VRAM used/total, e.g. "25.4/121.7 GB".
    static func hostVRAMUsedTotalLabel(_ metrics: HostMetricsPayload?) -> String? {
        guard let gpu = primaryGPU(metrics),
              let used = gpu.vramUsedMB,
              let total = gpu.vramTotalMB,
              total > 0
        else { return nil }
        return String(format: "%.1f/%.1f GB", used / 1024, total / 1024)
    }

    static func hostVRAMPercent(_ metrics: HostMetricsPayload?) -> Double? {
        guard let gpu = primaryGPU(metrics),
              let used = gpu.vramUsedMB,
              let total = gpu.vramTotalMB,
              total > 0
        else { return nil }
        return (used / total) * 100
    }
}
