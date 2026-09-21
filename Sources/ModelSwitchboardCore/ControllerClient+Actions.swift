import Foundation

extension ControllerClient {
    public func start(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/start", payload: ProfileRequest(profile: profile))
    }

    public func stop(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/stop", payload: ProfileRequest(profile: profile))
    }

    public func restart(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/restart", payload: ProfileRequest(profile: profile))
    }

    public func activate(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/switch", payload: ProfileRequest(profile: profile))
    }

    public func runIntegration(id: String, action: String = "sync") async throws -> ControllerActionResponse {
        try await post("/api/integrations/run", payload: IntegrationRequest(integration: id, action: action))
    }

    public func stopAll() async throws -> ControllerActionResponse {
        try await post("/api/stop-all", payload: EmptyRequest())
    }

    public func setProfilesDirectory(_ path: String) async throws -> ControllerActionResponse {
        try await post(
            "/api/config/profiles-dir", payload: ProfilesDirectoryRequest(profiles_dir: path))
    }

    public func quickBenchmark(profiles: [String]? = nil, suite: String = "quick") async throws -> ControllerActionResponse {
        let payload = BenchmarkRequest(suite: suite, profiles: profiles)
        return try await post("/api/benchmark/start", payload: payload)
    }
}
