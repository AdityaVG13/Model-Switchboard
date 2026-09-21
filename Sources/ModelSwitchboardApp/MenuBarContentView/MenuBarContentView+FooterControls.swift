import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var stopButtonTitle: String {
        hub.hasRemoteGateways ? "Stop Everything" : "Stop All"
    }

    var stopButtonHelp: String {
        if !hasAnythingToStop {
            return "Nothing is running"
        }
        if hub.hasRemoteGateways {
            return "Stop every running model on this Mac and all remotes"
        }
        return "Stop every running local model"
    }

    /// True when any gateway (local or remote) still has a running process.
    var hasAnythingToStop: Bool {
        DashboardChromeMetrics.canStopAnything(
            isBusy: hub.isStopEverythingBusy,
            storesHaveRunning: hub.allStores.contains {
                $0.statuses.contains { $0.running && $0.isBoardVisible }
            },
            storesHavePending: hub.allStores.contains { !$0.pendingProfileActions.isEmpty }
        )
    }

    var syncableIntegrations: [ControllerIntegration] {
        store.integrations.filter { $0.capabilities.contains("sync") }
    }
}
