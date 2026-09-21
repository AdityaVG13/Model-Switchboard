import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func markProfilesStarting(_ profiles: [String]) {
        for profile in profiles {
            pendingProfileActions[profile] = .starting
            markProfile(profile, running: true, ready: false)
        }
    }

    func clearPendingProfileActions(_ profiles: [String]) {
        for profile in profiles {
            pendingProfileActions.removeValue(forKey: profile)
        }
    }
}
