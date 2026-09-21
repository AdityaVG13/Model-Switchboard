import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func teardown(_ runtime: GatewayRuntime) {
        runtime.store.stopAutoRefresh()
        runtime.forwardSyncTask?.cancel()
        runtime.forwardSyncTask = nil
        if let tunnel = runtime.tunnel {
            // Instance-unique control sockets mean a replacement tunnel for the
            // same gateway id can start immediately without racing this stop.
            // State callbacks are filtered by tunnel.instanceID so the old
            // stop()'s terminal .idle cannot poison the replacement.
            Task { await tunnel.stop() }
        }
    }
}
