import Foundation
import ModelSwitchboardCore

extension DashboardFilterPreferences {
    static func finalizedFilterIDs(_ out: [String]) -> [String] {
        if out.isEmpty {
            return defaultChipIDs
        }
        var ids = out
        if !ids.contains(DashboardFilterChip.all.id) {
            ids.insert(DashboardFilterChip.all.id, at: 0)
            if ids.count > maxChips {
                ids = Array(ids.prefix(maxChips))
            }
        }
        return ids
    }
}
