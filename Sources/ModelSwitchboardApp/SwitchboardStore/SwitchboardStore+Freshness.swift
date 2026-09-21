import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func statusFreshness(relativeTo now: Date) -> StatusFreshness {
        // Freshness is derived from the structured refresh state - never from
        // error-message text. `.cached` is the failedShowingCached provenance,
        // not a substring of the message copy.
        switch refreshState {
        case .failed, .blocked:
            return statuses.isEmpty ? .error : .stale
        case .failedShowingCached:
            return statuses.isEmpty ? .error : .cached
        case .refreshing(let held):
            switch held {
            case .failed, .blocked:
                return statuses.isEmpty ? .error : .stale
            case .cached:
                return statuses.isEmpty ? .error : .cached
            case nil:
                break
            }
            fallthrough
        case .idle, .refreshed:
            guard let lastUpdated else { return .error }
            if now.timeIntervalSince(lastUpdated) > Constants.statusStaleThresholdSeconds {
                return .stale
            }
            return .fresh
        }
    }

    func displayedRunningProfiles(relativeTo now: Date) -> Int {
        hasRecentBoardStatus(relativeTo: now) ? summary.runningProfiles : 0
    }

    func displayedReadyProfiles(relativeTo now: Date) -> Int {
        hasRecentBoardStatus(relativeTo: now) ? summary.readyProfiles : 0
    }

    /// Last known running/ready counts stay visible across a failed or in-flight
    /// refresh so the menu bar cannot flash `N` → `0` → `N` on every poll.
    func hasRecentBoardStatus(relativeTo now: Date) -> Bool {
        guard !statuses.isEmpty, let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) <= Constants.statusStaleThresholdSeconds
    }
}
