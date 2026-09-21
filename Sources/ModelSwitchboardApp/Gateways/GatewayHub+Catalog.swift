import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    var allStores: [SwitchboardStore] { [localStore] + enabledRemoteRuntimes.map(\.store) }

    var totalProfiles: Int {
        allStores.reduce(0) { $0 + $1.summary.totalProfiles }
    }

    var displayedReadyProfiles: Int {
        allStores.reduce(0) { $0 + $1.displayedReadyProfiles }
    }

    var displayedRunningProfiles: Int {
        allStores.reduce(0) { $0 + $1.displayedRunningProfiles }
    }

    var isStopEverythingBusy: Bool {
        allStores.contains { $0.pendingGlobalActions.contains(.stopAll) }
    }
}
