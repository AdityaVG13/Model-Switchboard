import SwiftUI
import ModelSwitchboardCore

@MainActor
enum RemoteHostsPresentation {
    static func subtitle(runtime: GatewayRuntime, metrics: HostMetricsPayload?, hideHostInfo: Bool) -> String {
        if let host = metrics?.host, !host.isEmpty {
            return DisplayPrivacy.host(host, hidden: hideHostInfo)
        }
        return DisplayPrivacy.connectionSummary(runtime.config.endpointSummary, hidden: hideHostInfo)
    }

    static func statusColor(
        runtime: GatewayRuntime,
        entry: RemoteHostMetricsMonitor.Entry,
        dotOff: Color
    ) -> Color {
        if runtime.tunnelState.isFailed { return DashboardTheme.stopRed }
        if entry.error != nil, entry.metrics == nil { return DashboardTheme.pendingOrange }
        if entry.metrics != nil { return DashboardTheme.runningGreen }
        return dotOff
    }

    static func metricAccessibilityLabel(label: String, value: String, detail: String?) -> String {
        if let detail = detail.nonEmptyWhitespaceTrimmed {
            return "\(label) \(value), \(detail)"
        }
        return "\(label) \(value)"
    }
}
