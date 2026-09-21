import Foundation

extension ControllerRouter {
  func profileAction(_ run: @escaping (String) throws -> Void) -> Route {
    { [self] request in
      let payload = try requestObject(request)
      try run(try requiredString(payload, key: "profile"))
      return try response(service.actionResponse())
    }
  }

  func mapped(_ error: ControllerError) -> ControllerHTTPResponse {
    let spec = httpSpec(for: error)
    return (try? self.error(status: spec.status, code: spec.code, message: spec.message)) ?? fallback()
  }

  func httpSpec(for error: ControllerError) -> (status: Int, code: String, message: String) {
    switch error {
    case .profileNotFound:
      return (404, "profile_not_found", "profile not found")
    case .profileConflict:
      return (409, "profile_conflict", error.description)
    case .usage:
      return (400, "usage_error", "invalid request")
    case .invalidConfiguration:
      return (400, "invalid_configuration", "invalid request")
    case .invalidProfile:
      return (400, "invalid_profile", "invalid request")
    case .unsupported:
      return (400, "unsupported_action", error.description)
    case .operationFailed:
      return (500, "internal_error", "internal server error")
    }
  }
}
