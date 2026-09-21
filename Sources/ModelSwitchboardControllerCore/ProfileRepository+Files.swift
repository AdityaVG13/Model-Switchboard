import Foundation

extension ProfileRepository {
  func listedProfileFiles() throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { ["env", "json"].contains($0.pathExtension.lowercased()) }
      .sorted {
        $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
          == .orderedAscending
      }
  }

  func loadProfile(from file: URL) -> ControllerProfile? {
    let name = file.deletingPathExtension().lastPathComponent
    do {
      let values =
        try file.pathExtension.lowercased() == "json" ? parseJSON(file) : parseEnvironment(file)
      return try ControllerProfile(name: name, values: values)
    } catch {
      // One bad file must not take down GET /api/status for every profile.
      fputs("[profiles] skipping \(file.lastPathComponent): \(error)\n", stderr)
      return nil
    }
  }
}
