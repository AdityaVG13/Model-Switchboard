import Foundation

public struct ControllerConfiguration: Sendable, Equatable {
  public static let defaultHost = "127.0.0.1"
  public static let defaultPort = 8877
  public static let minimumTokenBytes = 16
  public static let maximumBodyBytes = 64 * 1024

  public let root: URL
  public let host: String
  public let port: UInt16
  public let authToken: String?
  public let unsafeBind: Bool

  public init(
    root: URL,
    host: String = Self.defaultHost,
    port: UInt16 = UInt16(Self.defaultPort),
    authToken: String? = nil,
    unsafeBind: Bool = false
  ) throws {
    let token = authToken?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let token, !token.isEmpty, token.utf8.count < Self.minimumTokenBytes {
      throw ControllerError.invalidConfiguration(
        "auth token must be at least \(Self.minimumTokenBytes) bytes")
    }
    if !Self.isLoopback(host) {
      guard unsafeBind else {
        throw ControllerError.invalidConfiguration(
          "non-loopback controller bind requires --unsafe-bind: \(host)")
      }
      guard let token, !token.isEmpty else {
        throw ControllerError.invalidConfiguration(
          "non-loopback controller bind requires a bearer auth token")
      }
    }
    self.root = root.standardizedFileURL
    self.host = host
    self.port = port
    self.authToken = token.flatMap { $0.isEmpty ? nil : $0 }
    self.unsafeBind = unsafeBind
  }

  public var profilesDirectory: URL {
    root.appendingPathComponent("model-profiles", isDirectory: true)
  }
  public var runDirectory: URL { root.appendingPathComponent("run", isDirectory: true) }
  public var benchmarkResultsDirectory: URL {
    root.appendingPathComponent("benchmark-results", isDirectory: true)
  }
  public var startScript: URL { root.appendingPathComponent("start-model-mac.sh") }
  public var stopAllScript: URL { root.appendingPathComponent("stop-all-models.sh") }
  public var activeProfileFile: URL { runDirectory.appendingPathComponent("active-profile") }
  public var droidStateFile: URL { root.appendingPathComponent(".droid-managed-models.json") }
  public var droidRemovedStateFile: URL {
    root.appendingPathComponent(".droid-removed-models.json")
  }

  public static func isLoopback(_ host: String) -> Bool {
    let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    return value == "localhost" || value == "127.0.0.1" || value == "::1"
  }

  public static func from(arguments: [String], currentDirectory: URL) throws
    -> ControllerConfiguration
  {
    let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Application Support/ModelSwitchboard/Controller", isDirectory: true)
    var root = defaultRoot
    var host = defaultHost
    var port = UInt16(defaultPort)
    var unsafeBind = false
    var token: String?
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--root":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --root")
        }
        root = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
      case "--host":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --host")
        }
        host = value
      case "--unsafe-bind":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --unsafe-bind")
        }
        host = value
        unsafeBind = true
      case "--port":
        guard let value = iterator.next(), let parsed = UInt16(value) else {
          throw ControllerError.usage("invalid value for --port")
        }
        port = parsed
      case "--auth-token":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --auth-token")
        }
        token = value
      case "--auth-token-file":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --auth-token-file")
        }
        token = try String(
          contentsOfFile: NSString(string: value).expandingTildeInPath, encoding: .utf8
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
      default:
        continue
      }
    }
    return try ControllerConfiguration(
      root: root, host: host, port: port, authToken: token, unsafeBind: unsafeBind)
  }
}

public enum ControllerError: Error, CustomStringConvertible, Sendable {
  case usage(String)
  case invalidConfiguration(String)
  case invalidProfile(String)
  case profileNotFound(String)
  case profileConflict(String)
  case operationFailed(String)
  case unsupported(String)

  public var description: String {
    switch self {
    case .usage(let message), .invalidConfiguration(let message), .invalidProfile(let message),
      .profileConflict(let message), .operationFailed(let message), .unsupported(let message):
      return message
    case .profileNotFound(let name):
      return "Unknown profile: \(name)"
    }
  }
}
