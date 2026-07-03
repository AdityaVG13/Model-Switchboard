import Foundation

/// One prefill-scaling measurement (context suite: prefill-1k/4k/8k).
public struct BenchmarkPrefillCase: Codable, Equatable, Sendable {
    public let label: String
    public let promptEstTokens: Int?
    public let ttftMS: Double?
    public let decodeTokensPerSec: Double?

    public init(
        label: String,
        promptEstTokens: Int?,
        ttftMS: Double?,
        decodeTokensPerSec: Double?
    ) {
        self.label = label
        self.promptEstTokens = promptEstTokens
        self.ttftMS = ttftMS
        self.decodeTokensPerSec = decodeTokensPerSec
    }

    enum CodingKeys: String, CodingKey {
        case label
        case promptEstTokens = "prompt_est_tokens"
        case ttftMS = "ttft_ms"
        case decodeTokensPerSec = "decode_tokens_per_sec"
    }
}

public struct BenchmarkLatestRow: Codable, Equatable, Sendable {
    public let profile: String?
    public let runtime: String?
    public let ttftMS: Double?
    public let decodeTokensPerSec: Double?
    public let e2eTokensPerSec: Double?
    public let rssMB: Double?
    /// Absent for suites without prefill cases and for reports cached before this field existed.
    public let prefillCases: [BenchmarkPrefillCase]?

    public init(
        profile: String?,
        runtime: String?,
        ttftMS: Double?,
        decodeTokensPerSec: Double?,
        e2eTokensPerSec: Double?,
        rssMB: Double?,
        prefillCases: [BenchmarkPrefillCase]? = nil
    ) {
        self.profile = profile
        self.runtime = runtime
        self.ttftMS = ttftMS
        self.decodeTokensPerSec = decodeTokensPerSec
        self.e2eTokensPerSec = e2eTokensPerSec
        self.rssMB = rssMB
        self.prefillCases = prefillCases
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case runtime
        case ttftMS = "ttft_ms"
        case decodeTokensPerSec = "decode_tokens_per_sec"
        case e2eTokensPerSec = "e2e_tokens_per_sec"
        case rssMB = "rss_mb"
        case prefillCases = "prefill_cases"
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
