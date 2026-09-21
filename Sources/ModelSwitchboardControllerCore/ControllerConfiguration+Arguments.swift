import Foundation
import ModelSwitchboardCore

extension ControllerConfiguration {
  public static func from(arguments: [String], currentDirectory: URL) throws
    -> ControllerConfiguration
  {
    let parsed = try parseArguments(arguments)
    var profilesDirectory = parsed.profilesDirectory
    if profilesDirectory == nil {
      profilesDirectory = loadConfiguredProfilesDirectory(root: parsed.root)
    } else if let profilesDirectory {
      try saveConfiguredProfilesDirectory(root: parsed.root, profilesDirectory: profilesDirectory)
    }
    return try ControllerConfiguration(
      root: parsed.root,
      host: parsed.host,
      port: parsed.port,
      authToken: parsed.token,
      unsafeBind: parsed.unsafeBind,
      profilesDirectory: profilesDirectory
    )
  }

  struct ParsedArguments {
    var root: URL
    var host: String
    var port: UInt16
    var unsafeBind: Bool
    var token: String?
    var profilesDirectory: URL?
  }
}
