import Foundation
import ModelSwitchboardCore

extension ControllerConfiguration {
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
    LoopbackHost.isLoopback(host)
  }
}
