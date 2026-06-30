import Foundation

extension ModelProfileStatus {
    var usesLoopbackEndpoint: Bool {
        LoopbackHost.isLoopbackURL(baseURL, fallbackHost: host)
    }
}
