import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func profileBadgeState(for profile: ModelProfileStatus, relativeTo now: Date) -> ProfileBadgeState {
        if let pending = pendingLabel(for: profile.profile) {
            return .pending(pending)
        }
        if profile.lifecycle.isActive && statusFreshness(relativeTo: now) != .fresh {
            return .stale
        }
        switch profile.lifecycle {
        case .running, .readyUnowned, .starting: return .running
        case .stopped: return .notRunning
        }
    }
}
