import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func runProfileAction(
        _ profile: String,
        label: ProfileAction,
        optimisticUpdate: () -> Void,
        action: @escaping (ControllerClient) async throws -> ControllerActionResponse,
        verify: ((ControllerClient) async throws -> Void)? = nil
    ) async {
        guard pendingProfileActions[profile] == nil else { return }
        noteManagedLoopbackTransition()
        pendingProfileActions[profile] = label
        let previousStatuses = statuses
        optimisticUpdate()
        defer { pendingProfileActions.removeValue(forKey: profile) }
        let succeeded = await run(
            action,
            verify: verify,
            actionName: label.displayName,
            profile: profile
        )
        if !succeeded {
            // Roll back optimistic running/ready flips on failure *or* cancel.
            statuses = previousStatuses
        }
    }
}
