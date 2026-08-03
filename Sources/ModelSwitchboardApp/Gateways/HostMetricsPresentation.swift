import Foundation
import ModelSwitchboardCore

/// Formats `HostMetricsPayload` for operator-facing chrome (hero, header, rows).
/// Never labels process RSS as VRAM — only nvidia-smi (or status `vram_mb`) counts.
enum HostMetricsPresentation {
    static func primaryGPU(_ metrics: HostMetricsPayload?) -> HostGPUMetrics? {
        metrics?.gpus.first
    }

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

    /// Row/hero memory chip: "54.0 GB VRAM" or "2.2 GB RSS" (never bare GB for RSS).
    static func profileMemoryLabel(
        status: ModelProfileStatus,
        metrics: HostMetricsPayload?,
        isRunning: Bool
    ) -> String? {
        guard isRunning else { return nil }
        if let vram = effectiveProfileVRAMMB(status: status, metrics: metrics) {
            return String(format: "%.1f GB VRAM", vram / 1024)
        }
        if let rss = status.rssMB {
            // Process resident set only — not GPU VRAM (often much smaller).
            return String(format: "%.1f GB RSS", rss / 1024)
        }
        return nil
    }

    /// Host-level VRAM used/total, e.g. "54/128 GB".
    static func hostVRAMUsedTotalLabel(_ metrics: HostMetricsPayload?) -> String? {
        guard let gpu = primaryGPU(metrics),
              let used = gpu.vramUsedMB,
              let total = gpu.vramTotalMB,
              total > 0
        else { return nil }
        return String(format: "%.0f/%.0f GB", used / 1024, total / 1024)
    }

    static func hostVRAMPercent(_ metrics: HostMetricsPayload?) -> Double? {
        guard let gpu = primaryGPU(metrics),
              let used = gpu.vramUsedMB,
              let total = gpu.vramTotalMB,
              total > 0
        else { return nil }
        return (used / total) * 100
    }

    static func hostGPUUtilPercent(_ metrics: HostMetricsPayload?) -> Double? {
        primaryGPU(metrics)?.utilPercent
    }

    static func hostGPUTempC(_ metrics: HostMetricsPayload?) -> Double? {
        primaryGPU(metrics)?.tempC
    }

    /// Compact gateway strip: "GPU 42% · 54/128 GB VRAM · 51°C".
    static func compactGPUStrip(_ metrics: HostMetricsPayload?) -> String? {
        guard metrics != nil else { return nil }
        var parts: [String] = []
        if let util = hostGPUUtilPercent(metrics) {
            parts.append(String(format: "GPU %.0f%%", util))
        }
        if let vram = hostVRAMUsedTotalLabel(metrics) {
            parts.append("\(vram) VRAM")
        }
        if let temp = hostGPUTempC(metrics) {
            parts.append(String(format: "%.0f°C", temp))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Section header chip under gateway name.
    static func sectionMetricsChip(_ metrics: HostMetricsPayload?) -> String? {
        compactGPUStrip(metrics)
    }

    static func percentLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }
}
