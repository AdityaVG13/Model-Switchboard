import Foundation
import ModelSwitchboardCore

extension DashboardFilterPreferences {
    /// Candidate runtime chips from live profiles + builtins (Settings picker).
    static func availableRuntimeChips(fromStatuses statuses: [ModelProfileStatus]) -> [DashboardFilterChip] {
        uniqueRuntimeChips(from: runtimeLabels(from: statuses))
    }

    static func runtimeLabels(from statuses: [ModelProfileStatus]) -> [String] {
        var labels: [String] = builtinRuntimeLabels
        for status in statuses {
            let label = status.runtimeLabel.nonEmptyTrimmed ?? status.runtime.trimmed
            guard !label.isEmpty else { continue }
            if let tags = status.runtimeTags {
                for tag in tags where tag.nonEmptyTrimmed != nil {
                    labels.append(tag)
                }
            }
            labels.append(label)
        }
        return labels
    }

    static func uniqueRuntimeChips(from labels: [String]) -> [DashboardFilterChip] {
        var seen = Set<String>()
        var chips: [DashboardFilterChip] = []
        for label in labels {
            let chip = DashboardFilterChip.runtime(label)
            guard !seen.contains(chip.id) else { continue }
            seen.insert(chip.id)
            chips.append(chip)
        }
        return chips.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
