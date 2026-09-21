import Foundation
import ModelSwitchboardCore

extension DashboardFilterPreferences {
    static func matches(
        _ status: ModelProfileStatus,
        filterID: String,
        isDisplayedRunning: Bool,
        isBusy: Bool
    ) -> Bool {
        if filterID == DashboardFilterChip.all.id {
            return true
        }
        if filterID == DashboardFilterChip.running.id {
            return isDisplayedRunning || isBusy
        }
        guard filterID.hasPrefix("runtime:") else {
            // Unknown / stale selection must not silently match everything.
            return false
        }
        let needle = String(filterID.dropFirst("runtime:".count))
        guard !needle.isEmpty else { return false }
        return runtimeMatches(status, needle: needle)
    }

    static func runtimeHaystack(_ status: ModelProfileStatus) -> String {
        ([status.runtime, status.runtimeLabel ?? "", status.command ?? ""] + (status.runtimeTags ?? []))
            .joined(separator: " ")
            .lowercased()
    }

    /// Legacy classification used by older tests / call sites.
    static func legacyRuntimeKind(_ status: ModelProfileStatus) -> String? {
        let haystack = runtimeHaystack(status)
        if haystack.contains("llama") { return "llama.cpp" }
        if haystack.contains("mlx") { return "mlx" }
        return nil
    }
}
