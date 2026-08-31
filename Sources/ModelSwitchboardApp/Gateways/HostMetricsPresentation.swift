import Foundation
import ModelSwitchboardCore

/// Formats `HostMetricsPayload` for operator-facing chrome (hero, header, rows).
/// Never labels process RSS as VRAM - only nvidia-smi (or status `vram_mb`) counts.
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
            // Process resident set only - not GPU VRAM (often much smaller).
            return String(format: "%.1f GB RSS", rss / 1024)
        }
        return nil
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

    static func hostGPUUtilPercent(_ metrics: HostMetricsPayload?) -> Double? {
        primaryGPU(metrics)?.utilPercent
    }

    static func hostGPUTempC(_ metrics: HostMetricsPayload?) -> Double? {
        primaryGPU(metrics)?.tempC
    }

    /// Compact gateway strip: "GPU 42% · 54.0/128.0 GB · 51°C".
    static func compactGPUStrip(_ metrics: HostMetricsPayload?) -> String? {
        guard metrics != nil else { return nil }
        var parts: [String] = []
        if let util = hostGPUUtilPercent(metrics) {
            parts.append(String(format: "GPU %.0f%%", util))
        }
        if let vram = hostVRAMUsedTotalLabel(metrics) {
            parts.append(vram)
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

    /// "up 3d 4h" style uptime label; nil when the host did not report it.
    static func uptimeLabel(_ metrics: HostMetricsPayload?) -> String? {
        guard let seconds = metrics?.uptimeSeconds, seconds >= 0 else { return nil }
        let duration = seconds
        let days = Int(duration / 86400)
        let hours = Int((duration.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        if days > 0 { return "up \(days)d \(hours)h" }
        if hours > 0 { return "up \(hours)h \(minutes)m" }
        return "up \(minutes)m"
    }

    /// "412.3/1830.0 GB" storage label; nil when unavailable.
    static func storageLabel(_ metrics: HostMetricsPayload?) -> String? {
        guard let storage = metrics?.storage,
              let total = storage.totalMB, total > 0
        else { return nil }
        let used = storage.usedMB ?? 0
        return String(format: "%.1f/%.1f GB", used / 1024, total / 1024)
    }

    /// "↓ 1.2 · ↑ 0.3 MB/s" network label; nil until the second sample.
    static func networkLabel(_ metrics: HostMetricsPayload?) -> String? {
        guard let network = metrics?.network else { return nil }
        let rx = network.rxKbps.map { $0 / 1024 }
        let tx = network.txKbps.map { $0 / 1024 }
        guard rx != nil || tx != nil else { return nil }
        let rxText = rx.map { String(format: "%.1f", $0) } ?? "-"
        let txText = tx.map { String(format: "%.1f", $0) } ?? "-"
        return "↓ \(rxText) · ↑ \(txText) MB/s"
    }

    /// Tailnet state for the Remote Hosts card: short label + detail.
    static func tailnetLabel(_ metrics: HostMetricsPayload?) -> (label: String, detail: String?)? {
        guard let tailnet = metrics?.tailscale else { return nil }
        let warnings = tailnet.health
        if tailnet.online == false {
            return (label: "TAILNET OFF", detail: warnings.first)
        }
        if !warnings.isEmpty {
            return (label: "TAILNET WARN", detail: warnings.first)
        }
        if tailnet.online == true {
            return (label: "TAILNET OK", detail: tailnet.ipv4)
        }
        return nil
    }

    /// Compact tok/s label for a running row: "42.3 tok/s" or nil.
    static func servingRateLabel(_ status: ModelProfileStatus) -> String? {
        guard let tokS = status.serving?.tokS, tokS > 0 else { return nil }
        if tokS >= 100 {
            return String(format: "%.0f tok/s", tokS)
        }
        return String(format: "%.1f tok/s", tokS)
    }

    static func percentLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int(value.rounded()))%"
    }
}
