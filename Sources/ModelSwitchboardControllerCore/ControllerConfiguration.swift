import Foundation
import ModelSwitchboardCore

public struct ControllerConfiguration: Sendable, Equatable {
  public static let defaultHost = ControllerEndpointDefaults.host
  public static let defaultPort = Int(ControllerEndpointDefaults.port)
  public static let minimumTokenBytes = 16
  public static let maximumBodyBytes = 64 * 1024

  public let root: URL
  public let host: String
  public let port: UInt16
  public let authToken: String?
  public let unsafeBind: Bool
  /// When set, profiles are read from this folder instead of `<root>/model-profiles`.
  public let profilesDirectoryOverride: URL?

  public init(
    root: URL,
    host: String = Self.defaultHost,
    port: UInt16 = ControllerEndpointDefaults.port,
    authToken: String? = nil,
    unsafeBind: Bool = false,
    profilesDirectory: URL? = nil
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
    self.profilesDirectoryOverride = profilesDirectory?.standardizedFileURL
  }

  public var profilesDirectory: URL {
    profilesDirectoryOverride
      ?? root.appendingPathComponent("model-profiles", isDirectory: true)
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
    var profilesDirectory: URL?
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--root":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --root")
        }
        root = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
      case "--profiles-dir":
        guard let value = iterator.next() else {
          throw ControllerError.usage("missing value for --profiles-dir")
        }
        profilesDirectory = URL(
          fileURLWithPath: NSString(string: value).expandingTildeInPath, isDirectory: true)
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
    if profilesDirectory == nil {
      profilesDirectory = Self.loadConfiguredProfilesDirectory(root: root)
    } else if let profilesDirectory {
      try Self.saveConfiguredProfilesDirectory(root: root, profilesDirectory: profilesDirectory)
    }
    return try ControllerConfiguration(
      root: root,
      host: host,
      port: port,
      authToken: token,
      unsafeBind: unsafeBind,
      profilesDirectory: profilesDirectory
    )
  }

  /// Optional `config.json` next to the controller root: `{ "profiles_dir": "…" }`.
  public static func loadConfiguredProfilesDirectory(root: URL) -> URL? {
    let configURL = root.appendingPathComponent("config.json")
    guard
      let data = try? Data(contentsOf: configURL),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let path = object["profiles_dir"] as? String,
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return URL(
      fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
  }

  public static func saveConfiguredProfilesDirectory(root: URL, profilesDirectory: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let configURL = root.appendingPathComponent("config.json")
    var payload: [String: Any] = [:]
    if FileManager.default.fileExists(atPath: configURL.path) {
      let data = try Data(contentsOf: configURL)
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ControllerError.operationFailed(
          "refusing to rewrite corrupt config.json: root value is not an object")
      }
      payload = object
    }
    payload["profiles_dir"] = profilesDirectory.path
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: configURL, options: .atomic)
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
