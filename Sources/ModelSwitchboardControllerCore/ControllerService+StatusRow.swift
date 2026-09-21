import Foundation
import ModelSwitchboardCore

extension ControllerService {
  public func status(for profile: ControllerProfile, allowPortFallback: Bool = true)
    -> ModelProfileStatus
  {
    let health = probeHealth(profile)
    let pid = resolvedPID(for: profile, allowPortFallback: allowPortFallback)
    let spec = profile.runtimeSpec
    return ModelProfileStatus(
      profile: profile.name,
      displayName: profile.displayName,
      runtime: profile.runtime,
      runtimeLabel: spec.label,
      runtimeTags: profile.runtimeTags,
      launchMode: spec.launchMode,
      host: profile.endpointHost,
      port: profile.endpointPort,
      baseURL: profile.baseURL,
      requestModel: profile.requestModel,
      serverModelID: profile.serverModelID,
      pid: pid,
      running: ProcessRunner.processIsAlive(pid),
      ready: health.ready,
      serverIDs: health.serverIDs,
      rssMB: rssMB(pid),
      command: processCommand(pid),
      logPath: profile.logPath,
      origin: .profile,
      missingArtifacts: [],
      serving: nil
    )
  }
}
