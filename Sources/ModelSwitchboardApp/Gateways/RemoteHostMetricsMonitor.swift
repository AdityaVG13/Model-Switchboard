import Foundation
import Observation
import ModelSwitchboardCore

/// Polls each enabled remote gateway for `GET /api/host/metrics`.
/// Older agents that lack the route degrade to a clear "unsupported" error.
@MainActor
@Observable
final class RemoteHostMetricsMonitor {
    struct Entry: Equatable {
        var metrics: HostMetricsPayload?
        var error: String?
        var updatedAt: Date?
        var unsupported: Bool = false
    }

    private(set) var entries: [String: Entry] = [:]

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private weak var hub: GatewayHub?
    @ObservationIgnored private let intervalSeconds: TimeInterval

    init(intervalSeconds: TimeInterval = 3) {
        self.intervalSeconds = intervalSeconds
    }

    func attach(hub: GatewayHub) {
        self.hub = hub
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(self?.intervalSeconds ?? 3))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func entry(forGatewayID id: String) -> Entry {
        entries[id] ?? Entry()
    }

    func pollOnce() async {
        guard let hub else { return }
        let runtimes = hub.enabledRemoteRuntimes
        let activeIDs = Set(runtimes.map(\.id))
        // Drop metrics for removed gateways.
        for id in entries.keys where !activeIDs.contains(id) {
            entries.removeValue(forKey: id)
        }
        // Sequential polls keep MainActor isolation simple; few remotes expected.
        for runtime in runtimes {
            let (id, entry) = await fetch(runtime: runtime)
            entries[id] = entry
        }
    }

    private func fetch(runtime: GatewayRuntime) async -> (String, Entry) {
        // SSH gateways need an established tunnel before the agent is reachable.
        if runtime.config.kind == .ssh, runtime.tunnelState != .established {
            var entry = entries[runtime.id] ?? Entry()
            entry.error = tunnelMessage(runtime.tunnelState)
            return (runtime.id, entry)
        }
        do {
            let client = try runtime.store.client
            let metrics = try await client.fetchHostMetrics()
            return (
                runtime.id,
                Entry(metrics: metrics, error: nil, updatedAt: Date(), unsupported: false)
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let unsupported = message.contains("404") || message.lowercased().contains("not found")
            var entry = entries[runtime.id] ?? Entry()
            entry.error = unsupported
                ? "This remote agent does not expose host metrics yet. Redeploy the agent to upgrade."
                : message
            entry.unsupported = unsupported
            entry.updatedAt = Date()
            // Keep last good metrics when a transient poll fails.
            return (runtime.id, entry)
        }
    }

    private func tunnelMessage(_ state: SSHTunnelManager.State) -> String {
        switch state {
        case .idle: return "SSH tunnel is off"
        case .connecting: return "SSH tunnel connecting…"
        case .established: return ""
        case .failed(let message): return message
        }
    }
}
