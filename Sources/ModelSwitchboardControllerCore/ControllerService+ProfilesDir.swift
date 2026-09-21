import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerService {
  public func setProfilesDirectory(_ path: String) throws -> ControllerActionResponse {
    guard let trimmed = path.nonEmptyTrimmed else {
      throw ControllerError.usage("missing required string field: profiles_dir")
    }
    let profilesDirectory = URL(
      fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    try fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    try ControllerConfiguration.saveConfiguredProfilesDirectory(
      root: configuration.root, profilesDirectory: profilesDirectory)
    configuration = try ControllerConfiguration(
      root: configuration.root,
      host: configuration.host,
      port: configuration.port,
      authToken: configuration.authToken,
      unsafeBind: configuration.unsafeBind,
      profilesDirectory: profilesDirectory
    )
    profiles = ProfileRepository(
      directory: configuration.profilesDirectory, fileManager: fileManager)
    return try actionResponse()
  }

  public func actionResponse() throws -> ControllerActionResponse {
    let payload = try statusPayload()
    return ControllerActionResponse(
      statuses: payload.statuses,
      benchmark: payload.benchmark,
      integrations: payload.integrations,
      profilesDirectory: payload.profilesDirectory,
      controllerRoot: payload.controllerRoot,
      error: nil
    )
  }
}
