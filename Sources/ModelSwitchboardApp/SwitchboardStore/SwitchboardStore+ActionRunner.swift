import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    @discardableResult
    func run(
        _ action: @escaping (ControllerClient) async throws -> ControllerActionResponse,
        verify: ((ControllerClient) async throws -> Void)? = nil,
        actionName: String? = nil,
        profile: String? = nil
    ) async -> Bool {
        do {
            let client = try self.client
            let response = try await action(client)
            applyActionResponse(response)
            try await verify?(client)
            cacheCurrentState()
            refreshState = .refreshed
            lastUpdated = Date()
            await syncAuxiliaryStateAfterMutation()
            return true
        } catch {
            if isBenignCancellation(error) { return false }
            recordRefreshFailure(error, actionName: actionName, profile: profile)
            return false
        }
    }
}
