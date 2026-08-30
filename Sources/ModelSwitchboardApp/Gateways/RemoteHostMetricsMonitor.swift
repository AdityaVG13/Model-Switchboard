import Foundation
import Observation
import ModelSwitchboardCore

/// Polls each enabled remote gateway for `GET /api/host/metrics`.
/// Older agents that lack the route degrade to a clear "unsupported" error.
@MainActor
@Observable
final class RemoteHostMetricsMonitor {
    /// Snapshot of one gateway's last metrics poll. `nonisolated` + `Sendable` so
    /// concurrent fetch tasks can carry previous/next values off the MainActor.
    nonisolated struct Entry: Equatable, Sendable {
        var metrics: HostMetricsPayload?
        var error: String?
        var updatedAt: Date?
        var unsupported: Bool = false
    }

    /// Work item prepared on MainActor, executed off it in a task group.
    private nonisolated struct PollTarget: Sendable {
        let id: String
        let previous: Entry
        /// Ready HTTP client for this gateway; nil when only an immediate result applies.
        let client: ControllerClient?
        /// Tunnel / client-build failure applied without network I/O.
        let immediateError: String?
        /// Match pre-parallel tunnel path: set error but leave `updatedAt` unchanged.
        let preserveUpdatedAt: Bool
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

        // Snapshot MainActor-only state (tunnel, client factory, prior entry) then
        // fan out independent HTTP fetches. Wall time ≈ max(RTT) not sum(RTT).
        var targets: [PollTarget] = []
        targets.reserveCapacity(runtimes.count)
        for runtime in runtimes {
            let previous = entries[runtime.id] ?? Entry()
            if runtime.config.kind == .ssh, runtime.tunnelState != .established {
                let tunnelError: String
                switch runtime.tunnelState {
                case .idle: tunnelError = "SSH tunnel is off"
                case .connecting: tunnelError = "SSH tunnel connecting…"
                case .established: tunnelError = ""
                case .failed(let message): tunnelError = message
                }
                targets.append(
                    PollTarget(
                        id: runtime.id,
                        previous: previous,
                        client: nil,
                        immediateError: tunnelError,
                        preserveUpdatedAt: true
                    )
                )
                continue
            }
            do {
                let client = try runtime.store.client
                targets.append(
                    PollTarget(
                        id: runtime.id,
                        previous: previous,
                        client: client,
                        immediateError: nil,
                        preserveUpdatedAt: false
                    )
                )
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                targets.append(
                    PollTarget(
                        id: runtime.id,
                        previous: previous,
                        client: nil,
                        immediateError: message,
                        preserveUpdatedAt: false
                    )
                )
            }
        }

        let results = await withTaskGroup(of: (String, Entry).self, returning: [(String, Entry)].self) { group in
            for target in targets {
                group.addTask {
                    await Self.resolveEntry(target: target)
                }
            }
            var collected: [(String, Entry)] = []
            collected.reserveCapacity(targets.count)
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        for (id, entry) in results {
            entries[id] = entry
        }
    }

    /// Runs per-gateway work without MainActor isolation (safe inside `TaskGroup`).
    private nonisolated static func resolveEntry(target: PollTarget) async -> (String, Entry) {
        if let immediate = target.immediateError {
            var entry = target.previous
            entry.error = immediate
            if !target.preserveUpdatedAt {
                entry.updatedAt = Date()
            }
            return (target.id, entry)
        }
        guard let client = target.client else {
            return (target.id, target.previous)
        }
        do {
            let metrics = try await client.fetchHostMetrics()
            return (
                target.id,
                Entry(metrics: metrics, error: nil, updatedAt: Date(), unsupported: false)
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let unsupported = message.contains("404") || message.lowercased().contains("not found")
            var entry = target.previous
            entry.error = unsupported
                ? "This remote agent does not expose host metrics yet (needs upgrade for GPU/VRAM)."
                : message
            entry.unsupported = unsupported
            entry.updatedAt = Date()
            // Keep last good metrics when a transient poll fails.
            return (target.id, entry)
        }
    }
}
