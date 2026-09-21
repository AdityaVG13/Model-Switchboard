import Foundation

public extension ModelProfileStatus {
    var usesLoopbackEndpoint: Bool {
        LoopbackHost.isLoopbackURL(baseURL, fallbackHost: host)
    }

    var displayHostRank: Int {
        isLoopbackHost ? 0 : 1
    }

    var normalizedDisplayHost: String {
        if isLoopbackHost {
            return "localhost"
        }
        return host.trimmed
    }

    var displayPortRank: Int {
        Int(port.trimmed) ?? .max
    }

    var isLoopbackHost: Bool {
        LoopbackHost.isLoopback(host)
    }
}
