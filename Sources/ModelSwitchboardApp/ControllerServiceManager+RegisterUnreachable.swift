import Foundation
import ServiceManagement

extension ControllerServiceManager {
    func registerUnreachableController() async {
        do {
            try await bootstrapIfNeeded()
            let service = SMAppService.agent(plistName: Self.plistName)
            let firstAttempt = !attemptedRegistration
            try registerIfNeeded(service)
            await waitAfterRegistration(service, firstAttempt: firstAttempt)
            lastDiagnostic = await isControllerReachable() ? nil : unreachableDiagnostic(for: service.status)
        } catch {
            await recoverFromRegistrationFailure(error)
        }
    }

    func bootstrapIfNeeded() async throws {
        if !didBootstrap {
            try bootstrapSupportDirectory()
            await removeLegacyLaunchAgent()
            didBootstrap = true
        }
    }
}
