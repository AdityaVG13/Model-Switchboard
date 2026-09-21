import Foundation
import ModelSwitchboardCore

extension HostMetricsPresentation {
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
        guard network.rxKbps != nil || network.txKbps != nil else { return nil }
        return "↓ \(mbpsText(network.rxKbps)) · ↑ \(mbpsText(network.txKbps)) MB/s"
    }

    static func mbpsText(_ kbps: Double?) -> String {
        kbps.map { String(format: "%.1f", $0 / 1024) } ?? "-"
    }
}
