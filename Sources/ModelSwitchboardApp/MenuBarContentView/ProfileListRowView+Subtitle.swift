import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var subtitle: String {
        var parts = [
            profile.runtimeLabel ?? profile.runtime,
            DisplayPrivacy.hostPort(profile.host, port: profile.port, hidden: hideHostInfo),
        ]
        appendStatusParts(to: &parts)
        appendThroughputParts(to: &parts)
        if showReachability, isDisplayedRunning, reachableEndpointURL == nil {
            parts.append(endpointUnavailableHint ?? "not reachable")
        }
        return parts.joined(separator: " · ")
    }

    func appendStatusParts(to parts: inout [String]) {
        if let pending {
            parts.append(pending.lowercased() + "…")
            return
        }
        if let memory = HostMetricsPresentation.profileMemoryLabel(
            status: profile,
            metrics: hostMetrics,
            isRunning: isDisplayedRunning
        ) {
            parts.append(memory)
        }
    }
}
