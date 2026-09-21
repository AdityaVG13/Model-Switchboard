import Foundation

public struct DashboardSummary: Equatable, Sendable {
    public let totalProfiles: Int
    public let runningProfiles: Int
    public let readyProfiles: Int
    public let benchmarkRunning: Bool
    public let benchmarkSuite: String?

    public init(payload: ControllerStatusPayload) {
        // Always derive Ready N/M from board-visible statuses. Agent
        // profile_*_count fields are informational and must not diverge the UI.
        self.init(
            counts: ProfileRuntimeCounts(statuses: payload.statuses),
            benchmark: payload.benchmark
        )
    }

    public init(counts: ProfileRuntimeCounts, benchmark: BenchmarkStatus?) {
        totalProfiles = counts.total
        runningProfiles = counts.running
        readyProfiles = counts.ready
        benchmarkRunning = benchmark?.running ?? false
        benchmarkSuite = benchmark?.latest?.suite
    }

    public var menuBarTitle: String {
        if benchmarkRunning {
            return "Bench \(readyProfiles)/\(totalProfiles)"
        }
        return "Ready \(readyProfiles)/\(totalProfiles)"
    }

    public var menuBarSystemImage: String {
        if benchmarkRunning {
            return "speedometer"
        }
        if readyProfiles > 0 {
            return "memorychip.fill"
        }
        if runningProfiles > 0 {
            return "memorychip"
        }
        return "cpu"
    }
}
