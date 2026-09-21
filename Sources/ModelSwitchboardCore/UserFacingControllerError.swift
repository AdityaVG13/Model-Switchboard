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
        if isTransientControllerClient(error) { return true }
        return nsErrorChain(error).contains(where: isTransientTransport)
    }

    static func isTransientControllerClient(_ error: Error) -> Bool {
        if case .invalidResponse = error as? ControllerClientError { return true }
        if case .httpError(let status, _) = error as? ControllerClientError {
            return (500..<600).contains(status)
        }
        return false
    }

    public static func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
            || nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ETIMEDOUT)
    }
}
