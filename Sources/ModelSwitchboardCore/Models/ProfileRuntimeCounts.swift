import Foundation

public struct ProfileRuntimeCounts: Equatable, Sendable {
    public let total: Int
    public let running: Int
    public let ready: Int

    public init(statuses: [ModelProfileStatus]) {
        total = statuses.count
        var runningCount = 0
        var readyCount = 0
        for status in statuses {
            if status.running { runningCount += 1 }
            if status.ready { readyCount += 1 }
        }
        running = runningCount
        ready = readyCount
    }
}
