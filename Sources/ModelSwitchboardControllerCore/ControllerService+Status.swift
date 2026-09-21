import Foundation
import ModelSwitchboardCore

extension ControllerService {
  public func statusPayload(selected: [String]? = nil) throws -> ControllerStatusPayload {
    let loaded = try profiles.load()
    let conflicts = profiles.conflicts(in: loaded)
    let names = selected ?? loaded.keys.sorted()
    let statuses = try statusRows(names: names, loaded: loaded, conflicts: conflicts)
    return ControllerStatusPayload(
      statuses: statuses,
      benchmark: benchmarks.status(),
      integrations: integrationStatus(),
      profilesDirectory: configuration.profilesDirectory.path,
      controllerRoot: configuration.root.path
    )
  }
}
