import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func probeLoopbackEndpointsIfNeeded(
        relativeTo now: Date = .now,
        allowDuringRefresh: Bool = false
    ) async {
        guard gateway.isLocal else { return }
        guard allowDuringRefresh || !isRefreshing else { return }
        guard shouldProbeLoopbackEndpoints(relativeTo: now) else { return }

        let candidates = loopbackEndpointProbeCandidates
        guard !candidates.isEmpty else { return }

        let unreachableProfiles = await collectUnreachableLoopbackProfiles(from: candidates)
        guard !unreachableProfiles.isEmpty else { return }
        markLoopbackEndpointsUnreachable(unreachableProfiles)
    }

    func collectUnreachableLoopbackProfiles(from candidates: [ModelProfileStatus]) async -> Set<String> {
        if usesCustomLoopbackEndpointProbe {
            return await loopbackEndpointProbe(candidates)
        }
        if loopbackEndpointProbeSession == nil {
            loopbackEndpointProbeSession = Self.makeLoopbackEndpointProbeSession()
        }
        guard let session = loopbackEndpointProbeSession else { return [] }
        return await Self.detectUnreachableLoopbackProfiles(in: candidates, using: session)
    }

    func markLoopbackEndpointsUnreachable(_ profiles: Set<String>) {
        var updated = statuses
        for index in updated.indices where profiles.contains(updated[index].profile) {
            updated[index] = updated[index].markingEndpointUnavailable()
        }
        statuses = updated
    }
}
