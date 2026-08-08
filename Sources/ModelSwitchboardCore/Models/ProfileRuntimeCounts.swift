import Foundation

public struct ProfileRuntimeCounts: Equatable, Sendable {
    public let total: Int
    public let running: Int
    public let ready: Int

    public init(total: Int, running: Int, ready: Int) {
        self.total = total
        self.running = running
        self.ready = ready
    }

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
    /// File-backed profiles only. Prefer wire `source`; fall back to port-/discovered- ids.
    public var isSyntheticDiscoveryProfile: Bool {
        if let source {
            switch source {
            case "profile":
                return false
            case "claim", "discovery":
                return true
            default:
                break
            }
        }
        return profile.hasPrefix("port-") || profile.hasPrefix("discovered-")
    }
}
