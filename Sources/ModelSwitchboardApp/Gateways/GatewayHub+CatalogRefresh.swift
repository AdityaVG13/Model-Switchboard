import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func stopEverything() async {
        // Unstructured MainActor-inheriting tasks: stores run their stop-alls
        // concurrently while each store mutation stays on the main actor.
        let tasks = allStores.map { store in
            Task { await store.stopAll() }
        }
        for task in tasks {
            await task.value
        }
    }

    func refreshAll() {
        let now = Date()
        // Manual refresh is already coalesced per-store via `isRefreshing`, but
        // the header used to swap controls on every press; still debounce the
        // kick so we do not stack remote status storms (~1s each).
        if let lastManualRefreshAt, now.timeIntervalSince(lastManualRefreshAt) < 0.75 {
            return
        }
        lastManualRefreshAt = now
        for store in allStores {
            Task { await store.refresh(includeDoctor: true) }
        }
    }
}
