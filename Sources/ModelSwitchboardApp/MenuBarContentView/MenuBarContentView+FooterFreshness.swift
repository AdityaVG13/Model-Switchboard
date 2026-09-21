import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    @ViewBuilder
    var footerFreshnessChip: some View {
        // Only tick when something is non-fresh - avoid a forever 1 Hz timer
        // while the board is healthy.
        let needsWatch = hub.allStores.contains { store in
            switch store.statusFreshness(relativeTo: .now) {
            case .fresh: false
            case .cached, .stale, .error: true
            }
        }
        if needsWatch {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let state = footerState(relativeTo: context.date) {
                    freshnessLabel(state)
                }
            }
        }
    }
}
