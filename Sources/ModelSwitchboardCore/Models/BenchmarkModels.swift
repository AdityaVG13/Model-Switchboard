import Foundation

public struct BenchmarkLatestRow: Codable, Equatable, Sendable {
    public let profile: String?
    public let runtime: String?
    public let ttftMS: Double?
    public let decodeTokensPerSec: Double?
    public let e2eTokensPerSec: Double?
    public let rssMB: Double?

    public init(
        profile: String?,
        runtime: String?,
        ttftMS: Double?,
        decodeTokensPerSec: Double?,
        e2eTokensPerSec: Double?,
        rssMB: Double?
    ) {
        self.profile = profile
        self.runtime = runtime
        self.ttftMS = ttftMS
        self.decodeTokensPerSec = decodeTokensPerSec
        self.e2eTokensPerSec = e2eTokensPerSec
        self.rssMB = rssMB
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case runtime
        case ttftMS = "ttft_ms"
        case decodeTokensPerSec = "decode_tokens_per_sec"
        case e2eTokensPerSec = "e2e_tokens_per_sec"
        case rssMB = "rss_mb"
    }
}

public struct BenchmarkLatestReport: Codable, Equatable, Sendable {
    public let generatedAt: String?
    public let suite: String?
    public let profiles: [String]
    public let rows: [BenchmarkLatestRow]
    public let jsonPath: String?
    public let markdownPath: String?

    public init(
        generatedAt: String?,
        suite: String?,
        profiles: [String],
        rows: [BenchmarkLatestRow],
        jsonPath: String?,
        markdownPath: String?
    ) {
        self.generatedAt = generatedAt
        self.suite = suite
        self.profiles = profiles
        self.rows = rows
        self.jsonPath = jsonPath
        self.markdownPath = markdownPath
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case suite
        case profiles
        case rows
        case jsonPath = "json_path"
        case markdownPath = "markdown_path"
    }
}

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
