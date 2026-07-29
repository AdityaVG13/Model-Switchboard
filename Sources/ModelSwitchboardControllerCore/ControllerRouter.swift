import Foundation

public struct ControllerHTTPRequest: Sendable, Equatable {
  public let method: String
  public let target: String
  public let headers: [String: String]
  public let body: Data

  public init(method: String, target: String, headers: [String: String] = [:], body: Data = Data())
  {
    self.method = method.uppercased()
    self.target = target
    self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
    self.body = body
  }

  public var path: String {
    URLComponents(string: target)?.path.nonEmpty ?? "/"
  }
}

public struct ControllerHTTPResponse: Sendable, Equatable {
  public let status: Int
  public let headers: [String: String]
  public let body: Data

  public init(
    status: Int, headers: [String: String] = ["Content-Type": "application/json"], body: Data
  ) {
    self.status = status
    self.headers = headers
    self.body = body
  }
}

public final class ControllerRouter: @unchecked Sendable {
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
      switch (request.method, request.path) {
      case ("GET", "/api/status"):
        let payload = try service.statusPayload()
        try? service.writeStatusCache(payload)
        return try response(payload)
      case ("GET", "/api/doctor"):
        return try response(service.doctor.report())
      case ("GET", "/api/benchmark/status"):
        return try response(service.benchmarks.status())
      case ("GET", "/api/integrations"):
        return try json([
          "integrations": try jsonObjects(service.integrationStatus()),
          "profiles_dir": service.configuration.profilesDirectory.path,
          "controller_root": service.configuration.root.path,
        ])
      case ("POST", "/api/start"):
        let payload = try requestObject(request)
        try service.start(try requiredString(payload, key: "profile"))
        return try response(service.actionResponse())
      case ("POST", "/api/stop"):
        let payload = try requestObject(request)
        try service.stop(try requiredString(payload, key: "profile"))
        return try response(service.actionResponse())
      case ("POST", "/api/restart"):
        let payload = try requestObject(request)
        try service.restart(try requiredString(payload, key: "profile"))
        return try response(service.actionResponse())
      case ("POST", "/api/switch"):
        let payload = try requestObject(request)
        try service.switchProfile(try requiredString(payload, key: "profile"))
        return try response(service.actionResponse())
      case ("POST", "/api/stop-all"):
        _ = try requestObject(request)
        try service.stopAll()
        return try response(service.actionResponse())
      case ("POST", "/api/integrations/run"):
        let payload = try requestObject(request)
        try service.runIntegration(
          try requiredString(payload, key: "integration"),
          action: payload["action"] as? String ?? "sync"
        )
        return try response(service.actionResponse())
      case ("POST", "/api/benchmark/start"):
        let payload = try requestObject(request)
        let selected = try optionalStrings(payload, key: "profiles")
        _ = try service.benchmarks.start(
          profiles: selected,
          suite: payload["suite"] as? String ?? "quick",
          allowConcurrent: payload["allow_concurrent"] as? Bool ?? false,
          keepRunning: payload["keep_running"] as? Bool ?? false
        )
        return try response(service.actionResponse())
      default:
        return try error(status: 404, code: "not_found", message: "not found")
      }
    } catch RouterError.invalidJSON {
      return (try? error(status: 400, code: "invalid_json", message: "invalid JSON")) ?? fallback()
    } catch let controllerError as ControllerError {
      switch controllerError {
      case .profileNotFound:
        return (try? error(status: 404, code: "profile_not_found", message: "profile not found"))
          ?? fallback()
      case .profileConflict:
        return
          (try? error(status: 409, code: "profile_conflict", message: "profile endpoint conflict"))
          ?? fallback()
      case .usage, .invalidConfiguration, .invalidProfile:
        return (try? error(status: 400, code: "invalid_request", message: "invalid request"))
          ?? fallback()
      case .unsupported:
        return
          (try? error(status: 400, code: "unsupported_action", message: controllerError.description))
          ?? fallback()
      case .operationFailed:
        return (try? error(status: 500, code: "internal_error", message: "internal server error"))
          ?? fallback()
      }
    } catch {
      return
        (try? self.error(status: 500, code: "internal_error", message: "internal server error"))
        ?? fallback()
    }
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
    try json(["ok": false, "error": code, "message": message], status: status)
  }

  private func jsonObjects<T: Encodable>(_ values: [T]) throws -> [Any] {
    let data = try JSONSupport.data(values)
    return try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
  }

  private func fallback() -> ControllerHTTPResponse {
    ControllerHTTPResponse(
      status: 500, body: Data("{\"ok\":false,\"error\":\"internal_error\"}".utf8))
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

extension String {
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
