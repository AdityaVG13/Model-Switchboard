import Foundation
import ServiceManagement

extension ControllerServiceManager {
    func waitAfterRegistration(_ service: SMAppService, firstAttempt: Bool) async {
        if service.status == .enabled {
            await waitForController(timeoutSeconds: 1.5)
        } else if firstAttempt {
            await launchDetachedControllerIfNeeded()
            await waitForController(timeoutSeconds: 2.0)
        }
    }

    func recoverFromRegistrationFailure(_ error: Error) async {
        Self.logger.error(
            "Controller registration failed: \(error.localizedDescription, privacy: .public)"
        )
        lastDiagnostic =
            "Could not register the local controller. Enable Model Switchboard in System Settings → General → Login Items & Extensions, then open the menu again."
        if !(await isControllerReachable()) {
            await launchDetachedControllerIfNeeded()
            await waitForController(timeoutSeconds: 2.0)
            if await isControllerReachable() {
                lastDiagnostic = nil
            }
        }
    }
}
