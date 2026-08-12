import Foundation
import OSLog

/// Cache-file envelope: `cachedAt` + the ONE status payload type.
///
/// The former twin struct (duplicated statuses/benchmark/integrations/
/// profilesDirectory/controllerRoot fields) and its hand-rolled field-by-field
/// mapper are deleted (L13). The payload now encodes nested under its own
/// keys. Old flat-shape cache files fail decode and are removed by `load` —
/// the cache is disposable, so the format change is self-migrating.
public struct CachedControllerStatusPayload: Codable, Equatable, Sendable {
    /// When the payload was captured (widget shows this as "cached at").
    public let cachedAt: Date
    /// The cached status payload — same type as the live wire payload.
    public let payload: ControllerStatusPayload

    public init(cachedAt: Date = .now, payload: ControllerStatusPayload) {
        self.cachedAt = cachedAt
        self.payload = payload
    }
}

extension CachedControllerStatusPayload: ControllerSourcePathProviding {
    public var profilesDirectory: String? { payload.profilesDirectory }
    public var controllerRoot: String? { payload.controllerRoot }
}

public enum ControllerStatusCache {
    private static let logger = Logger(subsystem: "io.modelswitchboard.core", category: "controller-status-cache")

    public static let cacheURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/io.modelswitchboard/controller-status.json")
    }()

    public static func load(from url: URL = cacheURL) -> CachedControllerStatusPayload? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileReadNoSuchFile.rawValue {
                return nil
            }
            logger.error("Cache read failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(CachedControllerStatusPayload.self, from: data)
        } catch {
            logger.error("Cache decode failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Cache cleanup failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return nil
        }
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
