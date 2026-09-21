import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    nonisolated static func userFacingErrorDescription(
        for error: Error,
        actionName: String? = nil,
        status: ModelProfileStatus? = nil,
        diagnostic: ProfileDiagnostic? = nil,
        isLocal: Bool = false
    ) -> String {
        if let mapped = mapATSError(error) {
            return mapped
        }
        if let mapped = UserFacingControllerError.description(for: error, isLocal: isLocal) {
            return mapped
        }
        guard UserFacingControllerError.isTimeout(error) else { return error.localizedDescription }
        return timeoutCopy(
            actionName: actionName,
            status: status,
            diagnostic: diagnostic,
            isLocal: isLocal
        )
    }
}
