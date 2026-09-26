import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    /// Local models featured as ACTIVE heroes: every running (or busy) profile
    /// that matches the active filter. Multi-start gateways can show several.
    var localHeroProfiles: [ModelProfileStatus] {
        // Closure instead of `filter(isLocalHero)`: passing that instance
        // method as a value trips GitHub Actions' Swift as a throwing
        // argument to `filter(rethrows:)`; local Swift 6.4 accepts it.
        store.sortedStatuses.filter { isLocalHero($0) }
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
