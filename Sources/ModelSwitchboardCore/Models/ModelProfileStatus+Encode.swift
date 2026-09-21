import Foundation

extension ModelProfileStatus {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeIdentity(&container)
        try encodeEndpoint(&container)
        try encodeProcess(&container)
    }

    func encodeIdentity(_ container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(profile, forKey: .profile)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeIfPresent(runtimeLabel, forKey: .runtimeLabel)
        try container.encodeIfPresent(runtimeTags, forKey: .runtimeTags)
        try container.encodeIfPresent(launchMode, forKey: .launchMode)
    }

    func encodeEndpoint(_ container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(requestModel, forKey: .requestModel)
        try container.encode(serverModelID, forKey: .serverModelID)
    }

    func encodeProcess(_ container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encodeIfPresent(pid, forKey: .pid)
        try container.encode(running, forKey: .running)
        try container.encode(ready, forKey: .ready)
        try container.encode(serverIDs, forKey: .serverIDs)
        try container.encodeIfPresent(rssMB, forKey: .rssMB)
        try container.encodeIfPresent(vramMB, forKey: .vramMB)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(logPath, forKey: .logPath)
        try container.encode(origin.rawValue, forKey: .origin)
        try container.encode(missingArtifacts ?? [], forKey: .missingArtifacts)
        try container.encode(serving, forKey: .serving)
    }
}
