import Foundation

public struct AutoRefreshPolicy: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case idle
        case activeRuntime
        case benchmarking
        case pendingAction
        /// Last refresh failed because the host was not reachable (DNS,
        /// connection refused, no route). Short cadence so Tailscale MagicDNS
        /// or a LaunchAgent coming up after reboot is not stuck on idle.
        case recovering
    }

    public static let idleInterval: TimeInterval = 600
    public static let activeRuntimeInterval: TimeInterval = 10
    public static let benchmarkingInterval: TimeInterval = 10
    public static let pendingActionInterval: TimeInterval = 5
    public static let recoveringInterval: TimeInterval = 3

    public let mode: Mode
    public let interval: TimeInterval

    public init(
        payload: ControllerStatusPayload,
        hasPendingActions: Bool = false,
        isRecovering: Bool = false
    ) {
        (mode, interval) = Self.resolved(
            payload: payload,
            hasPendingActions: hasPendingActions,
            isRecovering: isRecovering
        )
    }
}
