import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func applySuccessfulRefresh(includeDoctor: Bool) async throws {
        let client = try self.client
        let payload = try await client.fetchStatus()
        apply(payload: payload)
        cachePayload(payload, context: "refresh")
        // Refresh itself holds isRefreshing - allow the post-refresh probe.
        await probeLoopbackEndpointsIfNeeded(allowDuringRefresh: true)
        // Doctor is a second heavy pass on the agent. Auto-refresh only
        // fetches it once (or when the operator asked) so /api/status is
        // not stacked behind /api/doctor on a busy remote.
        if includeDoctor || doctorReport == nil {
            if let report = try? await client.fetchDoctorReport() {
                apply(doctorReport: report)
            }
        }
        isRecoveringFromTransportFailure = false
        refreshState = .refreshed
        lastUpdated = Date()
    }
}
