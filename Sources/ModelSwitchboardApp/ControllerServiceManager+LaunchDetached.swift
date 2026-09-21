import Darwin
import Foundation
import ModelSwitchboardCore
import ServiceManagement

extension ControllerServiceManager {
    func launchDetachedControllerIfNeeded() async {
        guard !(await isControllerReachable()) else { return }
        guard let binary = bundle.controllerBinaryURL else { return }

        let process = detachedControllerProcess(binary)
        do {
            try process.run()
            // Retain for the process lifetime. The LaunchAgent (KeepAlive) or a later relaunch
            // owns the long-lived serve; this keeps the fallback alive until then instead of
            // letting ARC reclaim it (which would tear the process down mid-run).
            detachedControllerProcess = process
            Self.logger.info("Launched detached controller (pid \(process.processIdentifier))")
        } catch {
            Self.logger.error(
                "Detached controller launch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
