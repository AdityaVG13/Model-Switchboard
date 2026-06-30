import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func run(
        _ action: @escaping (ControllerClient) async throws -> ControllerActionResponse,
        verify: ((ControllerClient) async throws -> Void)? = nil,
        actionName: String? = nil,
        profile: String? = nil
    ) async {
        do {
            let client = try self.client
            let response = try await action(client)
            if let statuses = response.statuses {
                self.statuses = statuses
                rememberLastActiveProfiles(from: statuses)
            }
            if let benchmark = response.benchmark { self.benchmark = benchmark }
            if let integrations = response.integrations { self.integrations = integrations }
            if let profilesDirectory = response.profilesDirectory { self.profilesDirectory = profilesDirectory }
            if let controllerRoot = response.controllerRoot { self.controllerRoot = controllerRoot }
            cacheCurrentState()
            try await verify?(client)
            lastError = nil
            lastUpdated = Date()
            await refresh()
        } catch {
            if isBenignCancellation(error) { return }
            lastError = Self.userFacingErrorDescription(
                for: error,
                actionName: actionName,
                status: profile.flatMap(statusForProfile),
                diagnostic: profile.flatMap(diagnosticForProfile)
            )
        }
    }

    func runProfileAction(
        _ profile: String,
        label: String,
        optimisticUpdate: () -> Void,
        action: @escaping (ControllerClient) async throws -> ControllerActionResponse,
        verify: ((ControllerClient) async throws -> Void)? = nil
    ) async {
        guard pendingProfileActions[profile] == nil else { return }
        noteManagedLoopbackTransition()
        pendingProfileActions[profile] = label
        optimisticUpdate()
        defer { pendingProfileActions.removeValue(forKey: profile) }
        await run(action, verify: verify, actionName: Self.actionName(forPendingLabel: label), profile: profile)
    }

    func verifyProfileStopped(_ profile: String, using client: ControllerClient) async throws {
        try await verifyProfilesStopped([profile], using: client)
    }

    func verifyProfilesStopped(_ profiles: Set<String>, using client: ControllerClient) async throws {
        guard !profiles.isEmpty else { return }
        let deadline = Date().addingTimeInterval(Constants.stopVerificationTimeoutSeconds)
        var survivingProfiles: [String] = []

        while true {
            let payload = try await client.fetchStatus()
            let surviving = payload.statuses.filter { profiles.contains($0.profile) && ($0.running || $0.ready) }
            if surviving.isEmpty {
                apply(payload: payload)
                cachePayload(payload, context: "stop-verification")
                return
            }
            survivingProfiles = surviving.map(\.displayName)
            if Date() >= deadline {
                break
            }
            try await Task.sleep(for: .seconds(Constants.stopVerificationPollSeconds))
        }

        throw ControllerClientError.serverError(
            "Stop returned but model process is still running: \(survivingProfiles.joined(separator: ", "))"
        )
    }

    func markProfile(_ profile: String, running: Bool, ready: Bool) {
        statuses = statuses.map { status in
            guard status.profile == profile else { return status }
            return status.updating(running: running, ready: ready)
        }
    }

    func apply(payload: ControllerStatusPayload) {
        statuses = payload.statuses
        rememberLastActiveProfiles(from: payload.statuses)
        benchmark = features.supportsBenchmarks ? payload.benchmark : nil
        if benchmark?.running == false {
            activeBenchmarkProfiles = []
        }
        integrations = features.supportsIntegrations ? payload.integrations : []
        profilesDirectory = payload.profilesDirectory
        controllerRoot = payload.controllerRoot
    }

    func apply(doctorReport: DoctorReport) {
        self.doctorReport = doctorReport
        profileDiagnostics = doctorReport.profiles.sorted(by: Self.compareDiagnostics)
    }

    func statusForProfile(_ profile: String) -> ModelProfileStatus? {
        statuses.first { $0.profile == profile }
    }

    func diagnosticForProfile(_ profile: String) -> ProfileDiagnostic? {
        profileDiagnostics.first { $0.profile == profile }
    }

    func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    nonisolated static func compareDiagnostics(lhs: ProfileDiagnostic, rhs: ProfileDiagnostic) -> Bool {
        let lhsSeverity = lhs.errors.isEmpty ? (lhs.warnings.isEmpty ? 0 : 1) : 2
        let rhsSeverity = rhs.errors.isEmpty ? (rhs.warnings.isEmpty ? 0 : 1) : 2
        if lhsSeverity != rhsSeverity { return lhsSeverity > rhsSeverity }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}
