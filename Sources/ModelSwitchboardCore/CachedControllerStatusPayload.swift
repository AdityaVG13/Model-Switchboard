import Foundation
import OSLog

/// Cache-file envelope: `cachedAt` + the ONE status payload type.
///
/// The former twin struct (duplicated statuses/benchmark/integrations/
/// profilesDirectory/controllerRoot fields) and its hand-rolled field-by-field
/// mapper are deleted (L13). The payload now encodes nested under its own
/// keys. Old flat-shape cache files fail decode and are removed by `load` -
/// the cache is disposable, so the format change is self-migrating.
public struct CachedControllerStatusPayload: Codable, Equatable, Sendable {
    /// When the payload was captured (widget shows this as "cached at").
    public let cachedAt: Date
    /// The cached status payload - same type as the live wire payload.
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
