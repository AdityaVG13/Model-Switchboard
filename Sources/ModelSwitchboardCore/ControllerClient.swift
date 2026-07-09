import Foundation

public enum ControllerClientError: LocalizedError {
    case invalidBaseURL(String)
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid controller URL: \(value)"
        case .invalidResponse:
            return "Invalid controller response"
        case .serverError(let value):
            return value
        }
    }
}

public struct ControllerClient: Sendable {
    private struct ProfileRequest: Encodable {
        let profile: String
    }

    private struct IntegrationRequest: Encodable {
        let integration: String
        let action: String
    }

    private struct BenchmarkRequest: Encodable {
        let suite: String
        let profiles: [String]?
    }

    private struct EmptyRequest: Encodable {}

    public let baseURL: URL
    public let authToken: String?
    public let session: URLSession
    public let decoder: JSONDecoder
    public let encoder: JSONEncoder

    public init(baseURL: URL, authToken: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.authToken = Self.normalizedAuthToken(authToken)
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public init(baseURLString: String, authToken: String? = nil, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURLString) else {
            throw ControllerClientError.invalidBaseURL(baseURLString)
        }
        self.init(baseURL: url, authToken: authToken, session: session)
    }

    public func fetchStatus() async throws -> ControllerStatusPayload {
        try await get("/api/status", as: ControllerStatusPayload.self)
    }

    public func fetchDoctorReport() async throws -> DoctorReport {
        try await get("/api/doctor", as: DoctorReport.self)
    }

    public func fetchBenchmarkStatus() async throws -> BenchmarkStatus {
        try await get("/api/benchmark/status", as: BenchmarkStatus.self)
    }

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

    public func quickBenchmark(profiles: [String]? = nil, suite: String = "quick") async throws -> ControllerActionResponse {
        let payload = BenchmarkRequest(suite: suite, profiles: profiles)
        return try await post("/api/benchmark/start", payload: payload)
    }

    /// Builds an API URL without percent-encoding path separators.
    /// Passing `"api/status"` to a single `appendingPathComponent` call can encode `/`
    /// as `%2F`, which the controller matches with exact path equality and would 404.
    public static func apiURL(baseURL: URL, path: String) -> URL {
        var url = baseURL
        for segment in path.split(separator: "/") where !segment.isEmpty {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: Self.apiURL(baseURL: baseURL, path: path))
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<Payload: Encodable>(_ path: String, payload: Payload) async throws -> ControllerActionResponse {
        var request = URLRequest(url: Self.apiURL(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try decoder.decode(ControllerActionResponse.self, from: data)
        if let error = decoded.error {
            throw ControllerClientError.serverError(error)
        }
        return decoded
    }

    private func applyAuth(to request: inout URLRequest) {
        guard let authToken, !authToken.isEmpty else { return }
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ControllerClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ControllerClientError.serverError(message)
        }
    }

    private static func normalizedAuthToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
