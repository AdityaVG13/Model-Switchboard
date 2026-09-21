import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func startAttachedMonitors() {
        if features.supportsBenchmarks {
            systemMetrics.start()
        } else {
            systemMetrics.stop()
        }
        syncHostMetricsMonitor(hasRemotes: hub.hasRemoteGateways)
    }

    func syncHostMetricsMonitor(hasRemotes: Bool) {
        hostMetricsMonitor.attach(hub: hub)
        if hasRemotes {
            hostMetricsMonitor.start()
        } else {
            hostMetricsMonitor.stop()
        }
    }
}
