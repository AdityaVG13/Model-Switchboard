import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func menuBarHelp(relativeTo now: Date) -> String {
        let scope = gateway.isLocal ? "Local" : gateway.name
        switch statusFreshness(relativeTo: now) {
        case .cached:
            return "Cached \(scope) model state may be stale. Refresh to verify live status."
        case .stale:
            return "\(scope) model status is stale. Refresh to verify live status."
        case .error where !statuses.isEmpty:
            return "\(scope) model status is unavailable. Refresh to verify live status."
        case .error, .fresh:
            // Display order matters here (matches the menu list); sortedStatuses is cached.
            return runningStatusesHelp()
        }
    }

    func isBusy(profile: String) -> Bool {
        pendingProfileActions[profile] != nil
    }

    func pendingLabel(for profile: String) -> String? {
        pendingProfileActions[profile]?.label
    }

    func isBenchmarkInFlight(for profile: String? = nil) -> Bool {
        if benchmark?.running == true { return true }
        if let profile {
            return pendingGlobalActions.contains(.benchmark(profile: profile))
                || pendingGlobalActions.contains(.benchmarkSelected)
                || pendingGlobalActions.contains(.benchmarkAll)
        }

        return pendingGlobalActions.contains(where: \.isBenchmark)
    }
}
