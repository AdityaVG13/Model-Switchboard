import Foundation
import ModelSwitchboardCore
import OSLog

/// Maintains one SSH tunnel to a remote gateway's loopback controller, plus
/// dynamic per-model port forwards over the same connection.
///
/// Runs `ssh -N` with `BatchMode=yes` (key/agent auth only - never passwords),
/// `ExitOnForwardFailure=yes`, and a ControlMaster socket so model-endpoint
/// forwards can be added and cancelled with `ssh -O` without reconnecting.
/// Restarts with jittered exponential backoff while the gateway stays enabled.
actor SSHTunnelManager {
    static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "ssh-tunnel")
    static let establishTimeoutSeconds: TimeInterval = 20
    static let establishPollSeconds: TimeInterval = 0.25
    static let stableUptimeSeconds: TimeInterval = 30
    static let maximumBackoffSeconds: TimeInterval = 60

    nonisolated let gatewayID: String
    nonisolated let configuration: Configuration
    /// Sticky local agent forward port. May be reassigned if the previous
    /// ephemeral bind is stolen before ssh starts (Address already in use).
    /// SAFETY: only mutated inside actor-isolated methods, and a UInt16 store
    /// is a single aligned store; readers (`localBaseURL`, argument builders)
    /// see either the old or the new port, never a torn value.
    nonisolated(unsafe) var localPort: UInt16
    /// Per-instance control socket leaf name. Must not be keyed only by gateway
    /// id: teardown is fire-and-forget, and a replacement manager for the same
    /// gateway would otherwise race ControlMaster on the old path.
    nonisolated let controlSocketFileName: String

    let executableURL: URL
    let onStateChange: @Sendable (UUID, State) async -> Void
    let onLocalPortChange: @Sendable (UUID, UInt16) async -> Void
    var state: State = .idle
    /// Remote model port → local loopback port. Local ports are unique per
    /// tunnel so two gateways can expose the same remote port (e.g. 8080)
    /// without colliding on this Mac.
    var activeForwards: [Int: Int] = [:]

    var desiredActive = false
    var process: Process?
    var supervisorTask: Task<Void, Never>?
    var consecutiveFailures = 0
    var stderrTail: [String] = []

    /// Per-instance id (not gateway id) - survives only for this manager object.
    nonisolated let instanceID: UUID

    init(
        gatewayID: String,
        configuration: Configuration,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        onStateChange: @escaping @Sendable (UUID, State) async -> Void = { _, _ in },
        onLocalPortChange: @escaping @Sendable (UUID, UInt16) async -> Void = { _, _ in }
    ) {
        self.gatewayID = gatewayID
        self.configuration = configuration
        self.executableURL = executableURL
        self.onStateChange = onStateChange
        self.onLocalPortChange = onLocalPortChange
        // Stable identity so Hub can ignore stale callbacks after a rebuild
        // replaces this tunnel while the old stop() is still finishing.
        self.instanceID = UUID()
        self.localPort = Self.allocateLoopbackPort()
        let shortID = String(gatewayID.replacingOccurrences(of: "-", with: "").prefix(12))
        let nonce = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        self.controlSocketFileName = "\(shortID)-\(nonce).sock"
    }
}
