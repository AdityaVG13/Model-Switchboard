import Foundation

extension UserFacingControllerError {
    static func mapControllerClient(_ error: Error, isLocal: Bool) -> String? {
        guard let error = error as? ControllerClientError else { return nil }
        switch error {
        case .httpError(let status, _):
            return httpStatusCopy(status, isLocal: isLocal)
        case .invalidResponse:
            return "Invalid controller response"
        case .serverError(let value):
            return serverErrorCopy(value)
        case .invalidBaseURL:
            return "Controller URL is invalid. Check Settings."
        }
    }

    static func httpStatusCopy(_ status: Int, isLocal: Bool) -> String {
        if status == 401 || status == 403 {
            return "Gateway rejected the request (auth). Check the bearer token in Settings."
        }
        if (500..<600).contains(status) {
            return isLocal
                ? "Local controller hit an internal error. Try Controller Doctor."
                : "Remote agent hit an internal error. Try Update, or check the agent log on the host."
        }
        return "Gateway HTTP \(status)."
    }

    static func serverErrorCopy(_ value: String) -> String {
        let trimmed = value.trimmed
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "Controller returned an error."
        }
        return value
    }
}
