import Foundation

extension ControllerClient {
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: Self.apiURL(baseURL: baseURL, path: path))
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func post<Payload: Encodable>(_ path: String, payload: Payload) async throws -> ControllerActionResponse {
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
}
