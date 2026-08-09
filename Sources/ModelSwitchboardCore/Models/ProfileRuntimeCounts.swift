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
        // Board census: same set as SwitchboardStore sortedStatuses (visible file-backed rows).
        let fileBacked = statuses.filter { !$0.isSyntheticDiscoveryProfile && $0.isBoardVisible }
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
    /// True for discovery/listening rows (not file-backed profiles or port claims).
    public var isSyntheticDiscoveryProfile: Bool {
        if let source {
            switch source {
            case "profile", "claim":
                return false
            case "discovery", "listening":
                return true
            default:
                break
            }
        }
        return profile.hasPrefix("discovered-")
    }
}
