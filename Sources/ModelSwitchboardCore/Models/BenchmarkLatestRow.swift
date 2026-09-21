import Foundation

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
