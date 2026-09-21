import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Last-active names that still exist as board-visible rows. Ghosts and
    /// hidden discovery listeners are dropped so Reopen cannot POST `start`
    /// for names the controller will 404.
    var reopenableLastActiveProfiles: [String] {
        lastActiveProfiles.filter { name in
            sortedStatuses.contains { $0.profile == name }
        }
    }

    var canReopenLastActive: Bool {
        features.supportsBenchmarks &&
        !reopenableLastActiveProfiles.isEmpty &&
        !pendingGlobalActions.contains(.reopenLastActive) &&
        !sortedStatuses.contains(where: \.running) &&
        pendingProfileActions.isEmpty
    }
}
