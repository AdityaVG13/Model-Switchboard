import Foundation

extension ModelProfileStatus {
    static func decodeIdentity(_ container: KeyedDecodingContainer<CodingKeys>) throws -> (
        profile: String, displayName: String, runtime: String,
        runtimeLabel: String?, runtimeTags: [String]?, launchMode: String?
    ) {
        (
            try container.decode(String.self, forKey: .profile),
            try container.decode(String.self, forKey: .displayName),
            try container.decode(String.self, forKey: .runtime),
            try container.decodeIfPresent(String.self, forKey: .runtimeLabel),
            try container.decodeIfPresent([String].self, forKey: .runtimeTags),
            try container.decodeIfPresent(String.self, forKey: .launchMode)
        )
    }

    static func decodeEndpoint(_ container: KeyedDecodingContainer<CodingKeys>) throws -> (
        host: String, port: String, baseURL: String, requestModel: String, serverModelID: String
    ) {
        (
            try container.decode(String.self, forKey: .host),
            try container.decode(String.self, forKey: .port),
            try container.decode(String.self, forKey: .baseURL),
            try container.decode(String.self, forKey: .requestModel),
            try container.decode(String.self, forKey: .serverModelID)
        )
    }

    static func decodeProcess(_ container: KeyedDecodingContainer<CodingKeys>) throws -> (
        pid: Int?, running: Bool, ready: Bool, serverIDs: [String],
        rssMB: Double?, vramMB: Double?, command: String?, logPath: String?,
        origin: Origin, missingArtifacts: [String], serving: ServingMetrics?
    ) {
        (
            try container.decodeIfPresent(Int.self, forKey: .pid),
            try container.decode(Bool.self, forKey: .running),
            try container.decode(Bool.self, forKey: .ready),
            try container.decodeIfPresent([String].self, forKey: .serverIDs) ?? [],
            try container.decodeIfPresent(Double.self, forKey: .rssMB),
            try container.decodeIfPresent(Double.self, forKey: .vramMB),
            try container.decodeIfPresent(String.self, forKey: .command),
            try container.decodeIfPresent(String.self, forKey: .logPath),
            Origin(wireValue: try container.decodeIfPresent(String.self, forKey: .origin)),
            try container.decodeIfPresent([String].self, forKey: .missingArtifacts) ?? [],
            try container.decodeIfPresent(ServingMetrics.self, forKey: .serving)
        )
    }
}
