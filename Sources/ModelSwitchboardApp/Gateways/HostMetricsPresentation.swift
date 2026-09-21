import Foundation
import ModelSwitchboardCore

/// Formats `HostMetricsPayload` for operator-facing chrome (hero, header, rows).
/// Never labels process RSS as VRAM - only nvidia-smi (or status `vram_mb`) counts.
enum HostMetricsPresentation {
    static func primaryGPU(_ metrics: HostMetricsPayload?) -> HostGPUMetrics? {
        metrics?.gpus.first
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
            // Process resident set only - not GPU VRAM (often much smaller).
            return String(format: "%.1f GB RSS", rss / 1024)
        }
        return nil
    }

    static func hostGPUUtilPercent(_ metrics: HostMetricsPayload?) -> Double? {
        primaryGPU(metrics)?.utilPercent
    }

    static func hostGPUTempC(_ metrics: HostMetricsPayload?) -> Double? {
        primaryGPU(metrics)?.tempC
    }
}
