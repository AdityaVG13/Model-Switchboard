import Foundation

/// Wire types for the controller HTTP listener. Kept separate from
/// route dispatch so the listener can parse requests without owning routes.
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

extension String {
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
