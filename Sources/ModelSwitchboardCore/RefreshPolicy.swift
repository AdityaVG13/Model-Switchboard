import Foundation

public struct AutoRefreshPolicy: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case idle
        case activeRuntime
        case benchmarking
        case pendingAction
    }

    public static let idleInterval: TimeInterval = 600
    public static let activeRuntimeInterval: TimeInterval = 10
    public static let benchmarkingInterval: TimeInterval = 10
    public static let pendingActionInterval: TimeInterval = 5

    public let mode: Mode
    public let interval: TimeInterval

    public init(payload: ControllerStatusPayload, hasPendingActions: Bool = false) {
        let summary = DashboardSummary(payload: payload)

        if hasPendingActions {
            mode = .pendingAction
            interval = Self.pendingActionInterval
            return
        }

        if summary.benchmarkRunning {
            mode = .benchmarking
            interval = Self.benchmarkingInterval
            return
        }

        if summary.runningProfiles > 0 || summary.readyProfiles > 0 {
            mode = .activeRuntime
            interval = Self.activeRuntimeInterval
            return
        }

        mode = .idle
        interval = Self.idleInterval
    }
}
