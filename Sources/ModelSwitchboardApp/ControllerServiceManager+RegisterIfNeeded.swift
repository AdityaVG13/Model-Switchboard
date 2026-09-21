import Foundation
import ServiceManagement

extension ControllerServiceManager {
    func registerIfNeeded(_ service: SMAppService) throws {
        switch service.status {
        case .notRegistered:
            try service.register()
        case .requiresApproval, .enabled, .notFound:
            break
        @unknown default:
            break
        }
        attemptedRegistration = true
    }
}
