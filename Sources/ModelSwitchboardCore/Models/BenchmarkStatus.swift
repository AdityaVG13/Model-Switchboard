import Foundation

public struct BenchmarkStatus: Codable, Equatable, Sendable {
    public let running: Bool
    public let pid: Int?
    public let logPath: String?
    public let latest: BenchmarkLatestReport?

    public init(running: Bool, pid: Int?, logPath: String?, latest: BenchmarkLatestReport?) {
        self.running = running
        self.pid = pid
        self.logPath = logPath
        self.latest = latest
    }

    enum CodingKeys: String, CodingKey {
        case running
        case pid
        case logPath = "log_path"
        case latest
    }
}
