import Foundation
import ModelSwitchboardCore

extension ControllerService {
  func resolvedPID(for profile: ControllerProfile, allowPortFallback: Bool) -> Int? {
    var pid = readPID(profile.name)
    if let current = pid, !ProcessRunner.processIsAlive(current) {
      try? fileManager.removeItem(at: pidFile(profile.name))
      pid = nil
    }
    if pid == nil, allowPortFallback, let listener = listenerPID(port: profile.endpointPort),
      processMatches(listener, profile: profile)
    {
      pid = listener
    }
    return pid
  }
}
