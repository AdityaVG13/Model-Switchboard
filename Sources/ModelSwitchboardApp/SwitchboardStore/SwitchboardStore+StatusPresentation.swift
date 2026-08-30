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
            let running = sortedStatuses.filter(\.running)
            guard !running.isEmpty else {
                return gateway.isLocal
                    ? "No local models running"
                    : "No models running on \(gateway.name)"
            }
            let prefix = gateway.isLocal ? "Running" : "\(gateway.name)"
            return "\(prefix): " + running.map(\.displayName).joined(separator: ", ")
        }
    }

    func statusFreshness(relativeTo now: Date) -> StatusFreshness {
        // Freshness is derived from the structured refresh state - never from
        // error-message text. `.cached` is the failedShowingCached provenance,
        // not a substring of the message copy.
        switch refreshState {
        case .failed, .blocked:
            return statuses.isEmpty ? .error : .stale
        case .failedShowingCached:
            return statuses.isEmpty ? .error : .cached
        case .idle, .refreshing, .refreshed:
            guard let lastUpdated else { return .error }
            if now.timeIntervalSince(lastUpdated) > Constants.statusStaleThresholdSeconds {
                return .stale
            }
            return .fresh
        }
    }

    func displayedRunningProfiles(relativeTo now: Date) -> Int {
        statusFreshness(relativeTo: now) == .fresh ? summary.runningProfiles : 0
    }

    func displayedReadyProfiles(relativeTo now: Date) -> Int {
        statusFreshness(relativeTo: now) == .fresh ? summary.readyProfiles : 0
    }

    func profileBadgeState(for profile: ModelProfileStatus, relativeTo now: Date) -> ProfileBadgeState {
        if let pending = pendingLabel(for: profile.profile) {
            return .pending(pending)
        }
        if profile.running && statusFreshness(relativeTo: now) != .fresh {
            return .stale
        }
        return profile.running ? .running : .notRunning
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
