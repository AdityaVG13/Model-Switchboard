import Foundation
import OSLog

extension ControllerStatusCache {
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
