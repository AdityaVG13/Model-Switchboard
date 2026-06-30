import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    static func userFacingErrorDescription(
        for error: Error,
        actionName: String? = nil,
        status: ModelProfileStatus? = nil,
        diagnostic: ProfileDiagnostic? = nil
    ) -> String {
        guard isTimeout(error) else { return error.localizedDescription }

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

    static func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    static func actionName(forPendingLabel label: String) -> String {
        switch label {
        case "ACTIVATING": return "Activate"
        case "STARTING": return "Start"
        case "STOPPING": return "Stop"
        case "RESTARTING": return "Restart"
        default: return label.capitalized
        }
    }
}
