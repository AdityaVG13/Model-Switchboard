import Foundation

/// Live serving rates decoded from the agent's status row `serving` object.
/// All fields optional: old agents omit `serving` entirely, and even current
/// agents report nulls when the backend probe fails.
public struct ServingMetrics: Codable, Equatable, Sendable {
    public let backend: String?
    public let tokS: Double?
    public let promptTokS: Double?
    public let kvCacheUsage: Double?
    public let requestsRunning: Double?
    public let requestsWaiting: Double?

    public init(
        backend: String? = nil,
        tokS: Double? = nil,
        promptTokS: Double? = nil,
        kvCacheUsage: Double? = nil,
        requestsRunning: Double? = nil,
        requestsWaiting: Double? = nil
    ) {
        self.backend = backend
        self.tokS = tokS
        self.promptTokS = promptTokS
        self.kvCacheUsage = kvCacheUsage
        self.requestsRunning = requestsRunning
        self.requestsWaiting = requestsWaiting
    }

    enum CodingKeys: String, CodingKey {
        case backend
        case tokS = "tok_s"
        case promptTokS = "prompt_tok_s"
        case kvCacheUsage = "kv_cache_usage"
        case requestsRunning = "requests_running"
        case requestsWaiting = "requests_waiting"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backend = try container.decodeIfPresent(String.self, forKey: .backend)
        tokS = try container.decodeIfPresent(Double.self, forKey: .tokS)
        promptTokS = try container.decodeIfPresent(Double.self, forKey: .promptTokS)
        kvCacheUsage = try container.decodeIfPresent(Double.self, forKey: .kvCacheUsage)
        requestsRunning = try container.decodeIfPresent(Double.self, forKey: .requestsRunning)
        requestsWaiting = try container.decodeIfPresent(Double.self, forKey: .requestsWaiting)
    }
}
