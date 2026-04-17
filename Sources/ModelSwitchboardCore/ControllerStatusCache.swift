import Foundation
import OSLog

public struct CachedControllerStatusPayload: Codable, Equatable, Sendable {
    public let cachedAt: Date
    public let statuses: [ModelProfileStatus]
    public let benchmark: BenchmarkStatus?
    public let integrations: [ControllerIntegration]
    public let profilesDirectory: String?
    public let controllerRoot: String?

    public init(
        cachedAt: Date = .now,
        statuses: [ModelProfileStatus],
        benchmark: BenchmarkStatus?,
        integrations: [ControllerIntegration],
        profilesDirectory: String? = nil,
        controllerRoot: String? = nil
    ) {
        self.cachedAt = cachedAt
        self.statuses = statuses
        self.benchmark = benchmark
        self.integrations = integrations
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
    }

    public init(cachedAt: Date = .now, payload: ControllerStatusPayload) {
        self.init(
            cachedAt: cachedAt,
            statuses: payload.statuses,
            benchmark: payload.benchmark,
            integrations: payload.integrations,
            profilesDirectory: payload.profilesDirectory,
            controllerRoot: payload.controllerRoot
        )
    }

    public var payload: ControllerStatusPayload {
        ControllerStatusPayload(
            statuses: statuses,
            benchmark: benchmark,
            integrations: integrations,
            profilesDirectory: profilesDirectory,
            controllerRoot: controllerRoot
        )
    }

    enum CodingKeys: String, CodingKey {
        case cachedAt = "cached_at"
        case statuses
        case benchmark
        case integrations
        case profilesDirectory = "profiles_dir"
        case controllerRoot = "controller_root"
    }
}

extension CachedControllerStatusPayload: ControllerSourcePathProviding {}

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
