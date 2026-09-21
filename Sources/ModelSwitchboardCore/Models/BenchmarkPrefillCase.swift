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
