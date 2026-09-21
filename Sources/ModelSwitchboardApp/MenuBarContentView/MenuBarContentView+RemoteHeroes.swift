import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Every remote running/busy profile matching the filter, for ACTIVE ON … cards.
    /// When This Mac already has local heroes, remotes still get their own cards.
    struct RemoteHeroSummary: Identifiable {
        var id: String { rowID }
        let rowID: String
        let gatewayID: String
        let name: String
        let profile: ModelProfileStatus
    }

    var remoteHeroSummaries: [RemoteHeroSummary] {
        var out: [RemoteHeroSummary] = []
        for runtime in hub.enabledRemoteRuntimes {
            for status in runtime.store.sortedStatuses {
                let running = MenuBarContentView.isDisplayedRunning(status, in: runtime.store)
                let busy = runtime.store.isBusy(profile: status.profile)
                guard running || busy else { continue }
                guard matchesFilter(status, in: runtime.store) else { continue }
                out.append(
                    RemoteHeroSummary(
                        rowID: "\(runtime.id)::\(status.profile)",
                        gatewayID: runtime.id,
                        name: runtime.name,
                        profile: status
                    )
                )
            }
        }
        return out
    }
}
