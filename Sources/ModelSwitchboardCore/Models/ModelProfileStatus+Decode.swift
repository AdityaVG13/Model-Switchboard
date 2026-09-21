import Foundation

extension ModelProfileStatus {
    /// Parse at the boundary: `log_path` absent/null decodes to nil (no
    /// invented `""`), `source` becomes the typed origin (unknown stays
    /// unknown, never guessed).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self(container: container)
    }

    init(container: KeyedDecodingContainer<CodingKeys>) throws {
        let identity = try Self.decodeIdentity(container)
        let endpoint = try Self.decodeEndpoint(container)
        let process = try Self.decodeProcess(container)
        self.init(
            profile: identity.profile,
            displayName: identity.displayName,
            runtime: identity.runtime,
            runtimeLabel: identity.runtimeLabel,
            runtimeTags: identity.runtimeTags,
            launchMode: identity.launchMode,
            host: endpoint.host,
            port: endpoint.port,
            baseURL: endpoint.baseURL,
            requestModel: endpoint.requestModel,
            serverModelID: endpoint.serverModelID,
            pid: process.pid,
            running: process.running,
            ready: process.ready,
            serverIDs: process.serverIDs,
            rssMB: process.rssMB,
            vramMB: process.vramMB,
            command: process.command,
            logPath: process.logPath,
            origin: process.origin,
            missingArtifacts: process.missingArtifacts,
            serving: process.serving
        )
    }
}
