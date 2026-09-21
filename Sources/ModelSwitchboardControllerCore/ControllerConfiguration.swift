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
    let token = authToken.nonEmptyTrimmed
    if let token, token.utf8.count < Self.minimumTokenBytes {
      throw ControllerError.invalidConfiguration(
        "auth token must be at least \(Self.minimumTokenBytes) bytes")
    }
    if !Self.isLoopback(host) {
      guard unsafeBind else {
        throw ControllerError.invalidConfiguration(
          "non-loopback controller bind requires --unsafe-bind: \(host)")
      }
      guard token != nil else {
        throw ControllerError.invalidConfiguration(
          "non-loopback controller bind requires a bearer auth token")
      }
    }
    self.root = root.standardizedFileURL
    self.host = host
    self.port = port
    self.authToken = token
    self.unsafeBind = unsafeBind
    self.profilesDirectoryOverride = profilesDirectory?.standardizedFileURL
  }
}
