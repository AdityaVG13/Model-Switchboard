import Foundation

public enum LoopbackHost {
    /// Single owner of loopback identity for app, controller, and scripts.
    /// Empty, `127.1`, and other 127/8 aliases are not loopback here.
    public static func isLoopback(_ host: String) -> Bool {
        let normalized = host.trimmed.strippingBrackets.lowercased()
        return normalized == "127.0.0.1" || normalized == "localhost" || normalized == "::1"
    }

    public static func isLoopbackURL(_ baseURL: String, fallbackHost: String) -> Bool {
        if let endpointHost = URL(string: baseURL)?.host {
            return isLoopback(endpointHost)
        }
        return isLoopback(fallbackHost)
    }
}
