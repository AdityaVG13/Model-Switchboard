import Foundation

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
