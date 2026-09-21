import Foundation

extension UserFacingControllerError {
    static func isTransientTransport(_ entry: NSError) -> Bool {
        if entry.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: entry.code) {
            case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed,
                 .cannotConnectToHost, .networkConnectionLost:
                return true
            default:
                return false
            }
        }
        if entry.domain == NSPOSIXErrorDomain {
            switch entry.code {
            case Int(ECONNREFUSED), Int(ENETUNREACH), Int(EHOSTUNREACH),
                 Int(ECONNRESET), Int(ENOTCONN), Int(ETIMEDOUT):
                return true
            default:
                return false
            }
        }
        return false
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
}
