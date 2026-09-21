import Foundation

public struct ControllerClient: Sendable {
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
}
