import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func shouldProbeLoopbackEndpoints(relativeTo now: Date = .now) -> Bool {
        !loopbackEndpointProbeCandidates.isEmpty && !isLoopbackEndpointProbeSuppressed(relativeTo: now)
    }

    func nextLoopbackEndpointProbeInterval(relativeTo now: Date = .now) -> TimeInterval {
        guard !loopbackEndpointProbeCandidates.isEmpty else {
            return Constants.loopbackEndpointProbeIdleIntervalSeconds
        }
        if let suppressedUntil = loopbackEndpointProbeSuppressedUntil, suppressedUntil > now {
            return max(0.5, suppressedUntil.timeIntervalSince(now))
        }
        if now < loopbackEndpointProbeFastUntil {
            return Constants.loopbackEndpointProbeFastIntervalSeconds
        }
        return Constants.loopbackEndpointProbeSteadyIntervalSeconds
    }

    func armLoopbackEndpointProbeFastWindow(relativeTo now: Date = .now) {
        loopbackEndpointProbeFastUntil = now.addingTimeInterval(Constants.loopbackEndpointProbeFastWindowSeconds)
    }

    func suppressLoopbackEndpointProbe(relativeTo now: Date = .now) {
        loopbackEndpointProbeSuppressedUntil = now.addingTimeInterval(Constants.loopbackEndpointProbeSuppressionSeconds)
    }

    func noteManagedLoopbackTransition(relativeTo now: Date = .now) {
        armLoopbackEndpointProbeFastWindow(relativeTo: now)
        suppressLoopbackEndpointProbe(relativeTo: now)
    }

    func isLoopbackEndpointProbeSuppressed(relativeTo now: Date) -> Bool {
        loopbackEndpointProbeSuppressedUntil.map { $0 > now } ?? false
    }
}
