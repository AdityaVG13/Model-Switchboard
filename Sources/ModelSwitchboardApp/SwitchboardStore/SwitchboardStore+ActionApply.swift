import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func applyActionResponse(_ response: ControllerActionResponse) {
        if let statuses = response.statuses {
            self.statuses = statuses
            rememberLastActiveProfiles(from: statuses)
        }
        if let benchmark = response.benchmark { self.benchmark = benchmark }
        if let integrations = response.integrations { self.integrations = integrations }
        if let profilesDirectory = response.profilesDirectory { self.profilesDirectory = profilesDirectory }
        if let controllerRoot = response.controllerRoot { self.controllerRoot = controllerRoot }
    }

    func stillRunning(_ profiles: Set<String>, in payload: ControllerStatusPayload) -> [ModelProfileStatus] {
        payload.statuses.filter { profiles.contains($0.profile) && ($0.running || $0.ready) }
    }

    func applyStopVerification(_ payload: ControllerStatusPayload, context: String) {
        apply(payload: payload)
        cachePayload(payload, context: context)
    }

    func apply(payload: ControllerStatusPayload, considerAutoBenchmark: Bool = true) {
        statuses = payload.statuses
        rememberLastActiveProfiles(from: payload.statuses)
        benchmark = payload.benchmark
        if benchmark?.running == false {
            activeBenchmarkProfiles = []
        }
        integrations = payload.integrations
        profilesDirectory = payload.profilesDirectory
        controllerRoot = payload.controllerRoot
        if considerAutoBenchmark {
            considerAutoBenchmarks()
        }
    }
}
