import Foundation
import ModelSwitchboardCore

extension RemoteHostMetricsMonitor {
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
}
