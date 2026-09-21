import Foundation

extension SwitchboardStore {
    enum Constants {
        static let lastActiveProfilesKey = "modelswitchboard.last-active-profiles"
        static let benchmarkCooldownKey = "modelswitchboard.last-benchmark-started-at"
        static let benchmarkCooldownSeconds: TimeInterval = 300
        static let autoBenchmarkedProfilesKey = "modelswitchboard.auto-benchmarked-profiles"
        static let statusStaleThresholdSeconds: TimeInterval = 900 // > AutoRefreshPolicy.idleInterval (600)
        static let loopbackEndpointProbeFastIntervalSeconds: TimeInterval = 2
        static let loopbackEndpointProbeSteadyIntervalSeconds: TimeInterval = 5
        static let loopbackEndpointProbeIdleIntervalSeconds: TimeInterval = 15
        static let loopbackEndpointProbeSuppressionSeconds: TimeInterval = 4
        static let loopbackEndpointProbeFastWindowSeconds: TimeInterval = 30
        static let loopbackEndpointProbeTimeoutSeconds: TimeInterval = 1
        static let stopVerificationTimeoutSeconds: TimeInterval = 10
        static let stopVerificationPollSeconds: TimeInterval = 0.5
    }
}
