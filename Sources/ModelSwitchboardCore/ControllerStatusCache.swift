import Foundation

public struct CachedControllerStatusPayload: Codable, Equatable, Sendable {
    public let cachedAt: Date
    public let statuses: [ModelProfileStatus]
    public let benchmark: BenchmarkStatus?
    public let integrations: [ControllerIntegration]

    public init(
        cachedAt: Date = .now,
        statuses: [ModelProfileStatus],
        benchmark: BenchmarkStatus?,
        integrations: [ControllerIntegration]
    ) {
        self.cachedAt = cachedAt
        self.statuses = statuses
        self.benchmark = benchmark
        self.integrations = integrations
    }

    public init(cachedAt: Date = .now, payload: ControllerStatusPayload) {
        self.init(
            cachedAt: cachedAt,
            statuses: payload.statuses,
            benchmark: payload.benchmark,
            integrations: payload.integrations
        )
    }

    public var payload: ControllerStatusPayload {
        ControllerStatusPayload(statuses: statuses, benchmark: benchmark, integrations: integrations)
    }

    enum CodingKeys: String, CodingKey {
        case cachedAt = "cached_at"
        case statuses
        case benchmark
        case integrations
    }
}

public enum ControllerStatusCache {
    public static let cacheURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/io.modelswitchboard/controller-status.json")
    }()

    public static func load(from url: URL = cacheURL) -> CachedControllerStatusPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedControllerStatusPayload.self, from: data)
    }

    public static func write(
        _ payload: ControllerStatusPayload,
        cachedAt: Date = .now,
        to url: URL = cacheURL
    ) throws {
        try write(CachedControllerStatusPayload(cachedAt: cachedAt, payload: payload), to: url)
    }

    public static func write(_ payload: CachedControllerStatusPayload, to url: URL = cacheURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
