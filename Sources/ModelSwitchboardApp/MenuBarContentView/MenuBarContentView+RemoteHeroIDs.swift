import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// First remote hero (compat for older helpers).
    var remoteActiveSummary: RemoteHeroSummary? {
        remoteHeroSummaries.first
    }

    /// Profile ids already featured as remote ACTIVE heroes, keyed by gateway.
    var remoteHeroProfileIDsByGateway: [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for summary in remoteHeroSummaries {
            map[summary.gatewayID, default: []].insert(summary.profile.profile)
        }
        return map
    }
}
