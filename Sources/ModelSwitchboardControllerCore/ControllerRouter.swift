import Foundation

public final class ControllerRouter: @unchecked Sendable {
  private struct RouteKey: Hashable {
    let method: String
    let path: String
  }

  private typealias Route = (ControllerHTTPRequest) throws -> ControllerHTTPResponse

  private let service: ControllerService
  private let authToken: String?

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

  private var routes: [RouteKey: Route] {
    [
      RouteKey(method: "GET", path: "/api/status"): { [self] _ in
        let payload = try service.statusPayload()
        try? service.writeStatusCache(payload)
        return try response(payload)
      },
      RouteKey(method: "GET", path: "/api/doctor"): { [self] _ in
        try response(service.doctor.report())
      },
      RouteKey(method: "GET", path: "/api/benchmark/status"): { [self] _ in
        try response(service.benchmarks.status())
      },
      RouteKey(method: "GET", path: "/api/integrations"): { [self] _ in
        try json([
          "integrations": try jsonObjects(service.integrationStatus()),
          "profiles_dir": service.configuration.profilesDirectory.path,
          "controller_root": service.configuration.root.path,
        ])
      },
      RouteKey(method: "POST", path: "/api/start"): profileAction(service.start),
      RouteKey(method: "POST", path: "/api/stop"): profileAction(service.stop),
      RouteKey(method: "POST", path: "/api/restart"): profileAction(service.restart),
      RouteKey(method: "POST", path: "/api/switch"): profileAction(service.switchProfile),
      RouteKey(method: "POST", path: "/api/stop-all"): { [self] request in
        _ = try requestObject(request)
        try service.stopAll()
        return try response(service.actionResponse())
      },
      RouteKey(method: "POST", path: "/api/config/profiles-dir"): { [self] request in
        let payload = try requestObject(request)
        return try response(
          service.setProfilesDirectory(try requiredString(payload, key: "profiles_dir")))
      },
      RouteKey(method: "POST", path: "/api/integrations/run"): { [self] request in
        let payload = try requestObject(request)
        try service.runIntegration(
          try requiredString(payload, key: "integration"),
          action: payload["action"] as? String ?? "sync"
        )
        return try response(service.actionResponse())
      },
      RouteKey(method: "POST", path: "/api/benchmark/start"): { [self] request in
        let payload = try requestObject(request)
        let selected = try optionalStrings(payload, key: "profiles")
        _ = try service.benchmarks.start(
          profiles: selected,
          suite: payload["suite"] as? String ?? "quick",
          allowConcurrent: JSONSupport.boolValue(payload["allow_concurrent"]) ?? false,
          keepRunning: JSONSupport.boolValue(payload["keep_running"]) ?? false
        )
        return try response(service.actionResponse())
      },
    ]
  }

  private func profileAction(_ run: @escaping (String) throws -> Void) -> Route {
    { [self] request in
      let payload = try requestObject(request)
      try run(try requiredString(payload, key: "profile"))
      return try response(service.actionResponse())
    }
  }

  private func mapped(_ error: ControllerError) -> ControllerHTTPResponse {
    let mapped: ControllerHTTPResponse?
    switch error {
    case .profileNotFound:
      mapped = try? self.error(status: 404, code: "profile_not_found", message: "profile not found")
    case .profileConflict:
      mapped = try? self.error(status: 409, code: "profile_conflict", message: error.description)
    case .usage:
      mapped = try? self.error(status: 400, code: "usage_error", message: "invalid request")
    case .invalidConfiguration:
      mapped = try? self.error(status: 400, code: "invalid_configuration", message: "invalid request")
    case .invalidProfile:
      mapped = try? self.error(status: 400, code: "invalid_profile", message: "invalid request")
    case .unsupported:
      mapped = try? self.error(status: 400, code: "unsupported_action", message: error.description)
    case .operationFailed:
      mapped = try? self.error(status: 500, code: "internal_error", message: "internal server error")
    }
    return mapped ?? fallback()
  }

  private func authorized(_ request: ControllerHTTPRequest) -> Bool {
    guard let authToken else { return true }
    return constantTimeEqual(request.headers["authorization"] ?? "", "Bearer \(authToken)")
  }

  private func requestObject(_ request: ControllerHTTPRequest) throws -> [String: Any] {
    if request.body.isEmpty { return [:] }
    do {
      guard let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
      else {
        throw ControllerError.usage("request body must be a JSON object")
      }
      return object
    } catch let error as ControllerError {
      throw error
    } catch {
      throw RouterError.invalidJSON
    }
  }

  private func requiredString(_ payload: [String: Any], key: String) throws -> String {
    guard let value = payload[key] as? String, !value.isEmpty else {
      throw ControllerError.usage("missing required string field: \(key)")
    }
    return value
  }

  private func optionalStrings(_ payload: [String: Any], key: String) throws -> [String]? {
    guard let value = payload[key] else { return nil }
    guard let strings = value as? [String] else {
      throw ControllerError.usage("\(key) must be a list of strings")
    }
    return strings
  }

  private func response<T: Encodable>(_ value: T, status: Int = 200) throws
    -> ControllerHTTPResponse
  {
    ControllerHTTPResponse(status: status, body: try JSONSupport.data(value))
  }

  private func json(_ value: [String: Any], status: Int = 200) throws -> ControllerHTTPResponse {
    ControllerHTTPResponse(status: status, body: try JSONSupport.data(value))
  }

  private func error(status: Int, code: String, message: String) throws -> ControllerHTTPResponse {
    try json(["error": code, "message": message], status: status)
  }

  private func jsonObjects<T: Encodable>(_ values: [T]) throws -> [Any] {
    let data = try JSONSupport.data(values)
    return try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
  }

  private func fallback() -> ControllerHTTPResponse {
    ControllerHTTPResponse(
      status: 500,
      body: Data("{\"error\":\"internal_error\",\"message\":\"internal error\"}".utf8))
  }

  private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var difference = UInt8(truncatingIfNeeded: left.count ^ right.count)
    for index in 0..<max(left.count, right.count) {
      difference |=
        (index < left.count ? left[index] : 0) ^ (index < right.count ? right[index] : 0)
    }
    return difference == 0
  }
}

private enum RouterError: Error { case invalidJSON }
