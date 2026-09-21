import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func verifyProfileStopped(_ profile: String, using client: ControllerClient) async throws {
        try await verifyProfilesStopped([profile], using: client)
    }

    func verifyProfilesStopped(_ profiles: Set<String>, using client: ControllerClient) async throws {
        guard !profiles.isEmpty else { return }
        let deadline = Date().addingTimeInterval(Constants.stopVerificationTimeoutSeconds)
        var survivingProfiles: [String] = []
        var lastPayload: ControllerStatusPayload?

        while true {
            let payload = try await client.fetchStatus()
            lastPayload = payload
            let surviving = stillRunning(profiles, in: payload)
            if surviving.isEmpty {
                applyStopVerification(payload, context: "stop-verification")
                return
            }
            survivingProfiles = surviving.map(\.displayName)
            if Date() >= deadline {
                break
            }
            try await Task.sleep(for: .seconds(Constants.stopVerificationPollSeconds))
        }

        if let lastPayload {
            applyStopVerification(lastPayload, context: "stop-verification-timeout")
        }

        throw ControllerClientError.serverError(
            "Stop returned but model process is still running: \(survivingProfiles.joined(separator: ", "))"
        )
    }
}
