import Foundation

public final class ProfileRepository: @unchecked Sendable {
  public let directory: URL
  let fileManager: FileManager

  public init(directory: URL, fileManager: FileManager = .default) {
    self.directory = directory
    self.fileManager = fileManager
  }

  public func load() throws -> [String: ControllerProfile] {
    guard fileManager.fileExists(atPath: directory.path) else { return [:] }
    let files: [URL]
    do {
      files = try listedProfileFiles()
    } catch {
      fputs("[profiles] skipping unreadable directory \(directory.path): \(error)\n", stderr)
      return [:]
    }
    var profiles: [String: ControllerProfile] = [:]
    for file in files {
      if let profile = loadProfile(from: file) {
        profiles[profile.name] = profile
      }
    }
    return profiles
  }

  public func profile(named name: String) throws -> ControllerProfile {
    guard let profile = try load()[name] else { throw ControllerError.profileNotFound(name) }
    return profile
  }

  public func load(file: URL) throws -> ControllerProfile {
    let name = file.deletingPathExtension().lastPathComponent
    let values = try parseValues(file: file)
    return try ControllerProfile(name: name, values: values)
  }

  public func parseValues(file: URL) throws -> [String: String] {
    try file.pathExtension.lowercased() == "json" ? parseJSON(file) : parseEnvironment(file)
  }
}
