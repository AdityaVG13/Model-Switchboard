import Foundation
import ModelSwitchboardCore

extension HostMetricsPresentation {
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
}
