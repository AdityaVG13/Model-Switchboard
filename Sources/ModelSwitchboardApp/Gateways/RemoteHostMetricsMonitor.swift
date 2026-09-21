import Foundation
import Observation
import ModelSwitchboardCore

/// Snapshot of one gateway's last metrics poll. File-level so GitHub Actions'
/// Swift accepts it as `Sendable` without a nested `nonisolated struct`.
struct RemoteHostMetricsEntry: Equatable, Sendable {
    var metrics: HostMetricsPayload?
    var error: String?
    var updatedAt: Date?
    var unsupported: Bool = false
}

/// Polls each enabled remote gateway for `GET /api/host/metrics`.
/// Older agents that lack the route degrade to a clear "unsupported" error.
@MainActor
@Observable
final class RemoteHostMetricsMonitor {
    typealias Entry = RemoteHostMetricsEntry

    var entries: [String: Entry] = [:]

    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored weak var hub: GatewayHub?
    @ObservationIgnored let intervalSeconds: TimeInterval

    init(intervalSeconds: TimeInterval = 3) {
        self.intervalSeconds = intervalSeconds
    }
}
