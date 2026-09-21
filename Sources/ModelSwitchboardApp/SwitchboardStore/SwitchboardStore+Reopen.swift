import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func reopenLastActive() async {
        guard canReopenLastActive else { return }
        let profiles = reopenableLastActiveProfiles
        guard pendingGlobalActions.insert(.reopenLastActive).inserted else { return }
        defer { pendingGlobalActions.remove(.reopenLastActive) }
        noteManagedLoopbackTransition()
        let previousStatuses = statuses

        markProfilesStarting(profiles)

        defer {
            clearPendingProfileActions(profiles)
        }

        do {
            let client = try self.client
            for profile in profiles {
                _ = try await client.start(profile: profile)
            }
            await refresh()
        } catch {
            if isBenignCancellation(error) {
                statuses = previousStatuses
                return
            }
            statuses = previousStatuses
            recordRefreshFailure(error)
        }
    }
}
