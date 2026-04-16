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
    public let baseURL: URL
    public let session: URLSession
    public let decoder: JSONDecoder
    public let encoder: JSONEncoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public init(baseURLString: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURLString) else {
            throw ControllerClientError.invalidBaseURL(baseURLString)
        }
        self.init(baseURL: url, session: session)
    }

    public func fetchStatus() async throws -> ControllerStatusPayload {
        try await get("/api/status", as: ControllerStatusPayload.self)
    }

    public func fetchBenchmarkStatus() async throws -> BenchmarkStatus {
        try await get("/api/benchmark/status", as: BenchmarkStatus.self)
    }

    public func start(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/start", payload: ["profile": profile])
    }

    public func stop(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/stop", payload: ["profile": profile])
    }

    public func restart(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/restart", payload: ["profile": profile])
    }

    public func activate(profile: String) async throws -> ControllerActionResponse {
        try await post("/api/switch", payload: ["profile": profile])
    }

    public func runIntegration(id: String, action: String = "sync") async throws -> ControllerActionResponse {
        try await post("/api/integrations/run", payload: ["integration": id, "action": action])
    }

    public func stopAll() async throws -> ControllerActionResponse {
        try await post("/api/stop-all", payload: [:])
    }

    public func quickBenchmark(profiles: [String]? = nil) async throws -> ControllerActionResponse {
        var payload: [String: Any] = ["suite": "quick"]
        if let profiles {
            payload["profiles"] = profiles
        }
        return try await post("/api/benchmark/start", payload: payload)
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post(_ path: String, payload: [String: Any]) async throws -> ControllerActionResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try decoder.decode(ControllerActionResponse.self, from: data)
        if let error = decoded.error {
            throw ControllerClientError.serverError(error)
        }
        return decoded
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
}
