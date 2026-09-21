import Foundation

extension ControllerClient {
    func applyAuth(to request: inout URLRequest) {
        guard let authToken, !authToken.isEmpty else { return }
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ControllerClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ControllerClientError.httpError(status: http.statusCode, body: message)
        }
    }

    static func normalizedAuthToken(_ token: String?) -> String? {
        token.nonEmptyTrimmed
    }
}
