import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func menuBarHelp(relativeTo now: Date) -> String {
        switch statusFreshness(relativeTo: now) {
        case .cached:
            return "Cached local model state may be stale. Refresh to verify live status."
        case .stale:
            return "Local model status is stale. Refresh to verify live status."
        case .error where !statuses.isEmpty:
            return "Local model status is unavailable. Refresh to verify live status."
        case .error, .fresh:
            // Display order matters here (matches the menu list); sortedStatuses is cached.
            let running = sortedStatuses.filter(\.running)
            guard !running.isEmpty else {
                return "No local models running"
            }
            return "Running: " + running.map(\.displayName).joined(separator: ", ")
        }
    }

    func statusFreshness(relativeTo now: Date) -> StatusFreshness {
        if let lastError, !lastError.isEmpty {
            if !statuses.isEmpty {
                if lastError.localizedCaseInsensitiveContains("cached") {
                    return .cached
                }
                return .stale
            }
            return .error
        }

        guard let lastUpdated else {
            return .error
        }

        if now.timeIntervalSince(lastUpdated) > Constants.statusStaleThresholdSeconds {
            return .stale
        }

        return .fresh
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
        pendingProfileActions[profile]
    }

    func isBenchmarkInFlight(for profile: String? = nil) -> Bool {
        if benchmark?.running == true { return true }
        if let profile {
            return pendingGlobalActions.contains("bench-\(profile)") ||
                pendingGlobalActions.contains("bench-selected") ||
                pendingGlobalActions.contains("bench-all")
        }

        if pendingGlobalActions.contains("bench-all") || pendingGlobalActions.contains("bench-selected") {
            return true
        }
        return pendingGlobalActions.contains(where: { $0.hasPrefix("bench-") })
    }
}
