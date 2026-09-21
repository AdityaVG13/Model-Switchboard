import Foundation

extension UserFacingControllerError {
    static func mapTransport(_ error: Error, isLocal: Bool) -> String? {
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
                if let message = mapPOSIX(entry, isLocal: isLocal) { return message }
            }
        }
        if error is DecodingError {
            return isLocal
                ? "Local controller returned an invalid response."
                : "Gateway returned an invalid response."
        }
        return nil
    }

    static func connectionRefusedCopy(isLocal: Bool) -> String {
        isLocal
            ? "Local controller refused the connection. It may still be starting."
            : "Gateway refused the connection. Is the agent running?"
    }
}
