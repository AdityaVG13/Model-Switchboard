import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Local models featured as ACTIVE heroes: every running (or busy) profile
    /// that matches the active filter. Multi-start gateways can show several.
    var localHeroProfiles: [ModelProfileStatus] {
        store.sortedStatuses.filter(isLocalHero)
    }

    /// Back-compat alias for call sites that still ask for "the" hero.
    var heroProfile: ModelProfileStatus? { localHeroProfiles.first }

    var localHeroProfileIDs: Set<String> {
        Set(localHeroProfiles.map(\.profile))
    }

    var standbyProfiles: [ModelProfileStatus] {
        let heroes = localHeroProfileIDs
        return store.sortedStatuses.filter { status in
            !heroes.contains(status.profile) && matchesFilter(status)
        }
    }
}
