import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var sortedStatuses: [ModelProfileStatus] {
        // Read `statuses` first so observers of `sortedStatuses` are tracked against it
        // even on a cache hit; the cache itself is @ObservationIgnored so filling it
        // during a SwiftUI body evaluation does not invalidate the in-flight render.
        let statuses = self.statuses
        if let sortedStatusesCache { return sortedStatusesCache }
        let sorted = statuses.boardVisible.sortedForDisplay()
        sortedStatusesCache = sorted
        return sorted
    }
}
