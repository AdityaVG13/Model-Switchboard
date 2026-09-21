import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var client: ControllerClient {
        get throws {
            try controllerClientFactory(controllerBaseURL, controllerAuthToken.nonEmptyTrimmed)
        }
    }

    var diagnosticsNeedingAttention: [ProfileDiagnostic] {
        profileDiagnostics.filter { !$0.errors.isEmpty || !$0.warnings.isEmpty }
    }

    var loopbackEndpointProbeCandidates: [ModelProfileStatus] {
        statuses.filter { status in
            status.isBoardVisible &&
                status.running &&
                status.ready &&
                status.usesLoopbackEndpoint &&
                pendingProfileActions[status.profile] == nil
        }
    }
}
