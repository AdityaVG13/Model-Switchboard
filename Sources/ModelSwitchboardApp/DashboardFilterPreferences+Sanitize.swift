import Foundation
import ModelSwitchboardCore

extension DashboardFilterPreferences {
    static func pinBuiltinChips(from ids: [String], seen: inout Set<String>, out: inout [String]) {
        if ids.contains(DashboardFilterChip.all.id) {
            appendUnique(DashboardFilterChip.all.id, seen: &seen, out: &out)
        }
        if ids.contains(DashboardFilterChip.running.id) {
            appendUnique(DashboardFilterChip.running.id, seen: &seen, out: &out)
        }
    }

    static func appendUnique(_ id: String, seen: inout Set<String>, out: inout [String]) {
        guard !id.isEmpty, !seen.contains(id) else { return }
        seen.insert(id)
        out.append(id)
    }

    static func appendRuntimeIDs(from ids: [String], seen: inout Set<String>, out: inout [String]) {
        for id in ids where id != DashboardFilterChip.all.id && id != DashboardFilterChip.running.id {
            guard out.count < maxChips else { break }
            if id.hasPrefix("runtime:"), id.count > "runtime:".count {
                appendUnique(id, seen: &seen, out: &out)
            }
        }
    }
}
