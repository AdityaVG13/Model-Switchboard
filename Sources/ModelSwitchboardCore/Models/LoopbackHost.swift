import Foundation

public enum LoopbackHost {
    public static func isLoopback(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "127.0.0.1" || normalized == "localhost" || normalized == "::1"
    }

    public static func isLoopbackURL(_ baseURL: String, fallbackHost: String) -> Bool {
        if let endpointHost = URL(string: baseURL)?.host {
            return isLoopback(endpointHost)
        }
        return isLoopback(fallbackHost)
    }
}
