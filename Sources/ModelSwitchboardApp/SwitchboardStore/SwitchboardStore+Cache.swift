import Foundation
import OSLog
import ModelSwitchboardCore

extension SwitchboardStore {
    func cacheCurrentState() {
        cachePayload(currentPayload, context: "state")
    }

    func cachePayload(_ payload: ControllerStatusPayload, context: String) {
        cachePayloadWriter(payload, context)
    }

    /// Default writer for remote-gateway stores: the shared cache file feeds the
    /// widget and local-controller migration, so remote payloads never touch it.
    nonisolated static func discardCachePayload(_ payload: ControllerStatusPayload, context: String) {}

    nonisolated static func writeCachePayload(_ payload: ControllerStatusPayload, context: String) {
        do {
            try ControllerStatusCache.write(payload)
        } catch {
            let logger = Logger(subsystem: "io.modelswitchboard.app", category: "switchboard-store")
            logger.error("Cache write failed (\(context, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }
}
