import Foundation

/// Shared copy for controller/gateway transport failures.
///
/// Owned here so the menu-bar app, widget, and host-metrics chips cannot
/// drift back to dumping raw JSON bodies or URLSession system strings.
public enum UserFacingControllerError {
    public static func description(for error: Error, isLocal: Bool = false) -> String? {
        if let mapped = mapControllerClient(error, isLocal: isLocal) {
            return mapped
        }
        return mapTransport(error, isLocal: isLocal)
    }

    /// DNS / refused / no-route / 5xx / decode failures clear once Tailscale
    /// or the local LaunchAgent is up. Auth and ATS are not in this set.
    public static func isTransient(_ error: Error) -> Bool {
        if isTimeout(error) { return true }
        if error is DecodingError { return true }
        if case .invalidResponse = error as? ControllerClientError { return true }
        if case .httpError(let status, _) = error as? ControllerClientError,
           (500..<600).contains(status) {
            return true
        }
        for entry in nsErrorChain(error) {
            if entry.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: entry.code) {
                case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed,
                     .cannotConnectToHost, .networkConnectionLost:
                    return true
                default:
                    break
                }
            } else if entry.domain == NSPOSIXErrorDomain {
                switch entry.code {
                case Int(ECONNREFUSED), Int(ENETUNREACH), Int(EHOSTUNREACH),
                     Int(ECONNRESET), Int(ENOTCONN), Int(ETIMEDOUT):
                    return true
                default:
                    break
                }
            }
        }
        return false
    }

    public static func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
            || nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ETIMEDOUT)
    }

    public static func nsErrorChain(_ error: Error) -> [NSError] {
        let nsError = error as NSError
        var chain: [NSError] = [nsError]
        var current: NSError? = nsError
        while let next = current?.userInfo[NSUnderlyingErrorKey] as? NSError {
            chain.append(next)
            current = next
        }
        return chain
    }

    private static func mapTransport(_ error: Error, isLocal: Bool) -> String? {
        for entry in nsErrorChain(error) {
            if entry.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: entry.code) {
                case .notConnectedToInternet:
                    return "No network route to the gateway."
                case .cannotFindHost, .dnsLookupFailed:
                    return isLocal
                        ? "Local controller host not found."
                        : "Gateway host not found. Check Tailscale / MagicDNS."
                case .cannotConnectToHost:
                    return connectionRefusedCopy(isLocal: isLocal)
                case .networkConnectionLost:
                    return "Connection to the gateway was lost."
                case .userAuthenticationRequired, .userCancelledAuthentication:
                    return "Gateway rejected the request (auth). Check the bearer token in Settings."
                default:
                    break
                }
            } else if entry.domain == NSPOSIXErrorDomain {
                switch entry.code {
                case Int(ECONNREFUSED):
                    return connectionRefusedCopy(isLocal: isLocal)
                case Int(ENETUNREACH), Int(EHOSTUNREACH):
                    return "No network route to the gateway."
                case Int(ECONNRESET), Int(ENOTCONN):
                    return "Connection to the gateway was lost."
                default:
                    break
                }
            }
        }
        if error is DecodingError {
            return isLocal
                ? "Local controller returned an invalid response."
                : "Gateway returned an invalid response."
        }
        return nil
    }

    private static func mapControllerClient(_ error: Error, isLocal: Bool) -> String? {
        guard let error = error as? ControllerClientError else { return nil }
        switch error {
        case .httpError(let status, _):
            if status == 401 || status == 403 {
                return "Gateway rejected the request (auth). Check the bearer token in Settings."
            }
            if (500..<600).contains(status) {
                return isLocal
                    ? "Local controller hit an internal error. Try Controller Doctor."
                    : "Remote agent hit an internal error. Try Update, or check the agent log on the host."
            }
            return "Gateway HTTP \(status)."
        case .invalidResponse:
            return "Invalid controller response"
        case .serverError(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                return "Controller returned an error."
            }
            return value
        case .invalidBaseURL:
            return nil
        }
    }

    private static func connectionRefusedCopy(isLocal: Bool) -> String {
        isLocal
            ? "Local controller refused the connection. It may still be starting."
            : "Gateway refused the connection. Is the agent running?"
    }
}
