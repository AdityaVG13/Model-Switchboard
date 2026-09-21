import Foundation

public final class ControllerRouter: @unchecked Sendable {
  struct RouteKey: Hashable {
    let method: String
    let path: String
  }

  typealias Route = (ControllerHTTPRequest) throws -> ControllerHTTPResponse

  let service: ControllerService
  let authToken: String?

  public init(service: ControllerService, authToken: String?) {
    self.service = service
    self.authToken = authToken
  }

  public func handle(_ request: ControllerHTTPRequest) -> ControllerHTTPResponse {
    do {
      if request.path.hasPrefix("/api/"), !authorized(request) {
        return try error(status: 401, code: "unauthorized", message: "unauthorized")
      }
      guard let route = routes[RouteKey(method: request.method, path: request.path)] else {
        return try error(status: 404, code: "not_found", message: "not found")
      }
      return try route(request)
    } catch RouterError.invalidJSON {
      return (try? error(status: 400, code: "invalid_json", message: "invalid JSON")) ?? fallback()
    } catch let controllerError as ControllerError {
      return mapped(controllerError)
    } catch {
      return
        (try? self.error(status: 500, code: "internal_error", message: "internal server error"))
        ?? fallback()
    }
  }
}

enum RouterError: Error { case invalidJSON }
