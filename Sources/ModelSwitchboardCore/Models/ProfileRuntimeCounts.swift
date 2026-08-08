import Foundation

public struct ProfileRuntimeCounts: Equatable, Sendable {
    public let total: Int
    public let running: Int
    public let ready: Int

    public init(statuses: [ModelProfileStatus]) {
        let fileBacked = statuses.filter { !$0.isSyntheticDiscoveryProfile }
        total = fileBacked.count
        var runningCount = 0
        var readyCount = 0
        for status in fileBacked {
            if status.running { runningCount += 1 }
            if status.ready { readyCount += 1 }
        }
        running = runningCount
        ready = readyCount
    }
}

extension ModelProfileStatus {
    /// Agent discovery rows use `port-N` / `discovered-N` ids; they are not file-backed profiles.
    public var isSyntheticDiscoveryProfile: Bool {
        profile.hasPrefix("port-") || profile.hasPrefix("discovered-")
    }
}
