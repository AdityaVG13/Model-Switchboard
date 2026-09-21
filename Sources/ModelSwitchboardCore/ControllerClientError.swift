import Foundation

public enum ControllerClientError: LocalizedError {
    case invalidBaseURL(String)
    case invalidResponse
    case serverError(String)
    case httpError(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid controller URL: \(value)"
        case .invalidResponse:
            return "Invalid controller response"
        case .serverError(let value):
            return Self.serverErrorCopy(value)
        case .httpError(let status, _):
            return Self.httpErrorCopy(status)
        }
    }

    static func serverErrorCopy(_ value: String) -> String {
        let trimmed = value.trimmed
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "Controller returned an error."
        }
        return value
    }

    static func httpErrorCopy(_ status: Int) -> String {
        // Never paint raw JSON bodies (`{"error":"internal_error"}`) onto
        // the dashboard, widget, or metrics chips.
        if status == 401 || status == 403 {
            return "Gateway rejected the request (auth)."
        }
        if (500..<600).contains(status) {
            return "Controller hit an internal error."
        }
        return "Gateway HTTP \(status)."
    }
}
