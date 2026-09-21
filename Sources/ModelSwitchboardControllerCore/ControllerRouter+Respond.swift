import Foundation

extension ControllerRouter {
  func response<T: Encodable>(_ value: T, status: Int = 200) throws
    -> ControllerHTTPResponse
  {
    ControllerHTTPResponse(status: status, body: try JSONSupport.data(value))
  }

  func json(_ value: [String: Any], status: Int = 200) throws -> ControllerHTTPResponse {
    ControllerHTTPResponse(status: status, body: try JSONSupport.data(value))
  }

  func error(status: Int, code: String, message: String) throws -> ControllerHTTPResponse {
    try json(["error": code, "message": message], status: status)
  }

  func jsonObjects<T: Encodable>(_ values: [T]) throws -> [Any] {
    let data = try JSONSupport.data(values)
    return try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
  }

  func fallback() -> ControllerHTTPResponse {
    ControllerHTTPResponse(
      status: 500,
      body: Data("{\"error\":\"internal_error\",\"message\":\"internal error\"}".utf8))
  }
}
