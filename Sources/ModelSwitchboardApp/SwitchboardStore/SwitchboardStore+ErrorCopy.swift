import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    nonisolated static func timeoutCopy(
        actionName: String?,
        status: ModelProfileStatus?,
        diagnostic: ProfileDiagnostic?,
        isLocal: Bool
    ) -> String {
        if !isLocal, actionName == nil, status == nil {
            return "Gateway status timed out. Last known models are still shown."
        }

        let profileName = status?.displayName ?? diagnostic?.displayName
        let subject = profileName.map { " for \($0)" } ?? ""
        let action = actionName ?? "Request"
        var message = "\(action) timed out\(subject)."

        if let profileError = diagnostic?.errors.first {
            message += " Profile issue: \(profileError)"
        } else {
            message += " The model may still be launching; refresh after it finishes or run Controller Doctor."
        }
        return message
    }
}
