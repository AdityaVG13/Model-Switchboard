import Foundation
import ServiceManagement

extension ControllerServiceManager {
    /// Registers the LaunchAgent and recovers a reachable loopback controller when needed.
    /// Suspends briefly while probing the port so diagnostics are accurate without blocking `App.init`.
    ///
    /// Safe to call again after Login Items approval: a previous `requiresApproval`
    /// or failed `register()` must not stick for the process lifetime.
    @discardableResult
    func ensureRegistered() async -> String? {
        guard bundledServiceAvailable else {
            return markMissingBundledController()
        }

        if await isControllerReachable() {
            lastDiagnostic = nil
            return nil
        }

        await registerUnreachableController()
        return lastDiagnostic
    }
}
