import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func trustedStopPID(name: String, profile: ControllerProfile, current: ModelProfileStatus) -> Int? {
        var primaryPID = current.pid
        if let pid = primaryPID, !processMatches(pid, profile: profile) {
            let owned = readPID(name)
            if owned == pid, ProcessRunner.processIsAlive(owned),
                commandLooksLikeModelServer(processCommand(pid))
            {
                return primaryPID
            }
            return nil
        }
        return primaryPID
    }

    func runStopCommand(_ profile: ControllerProfile) -> Error? {
        guard let command = profile["STOP_COMMAND"]?.nonEmptyTrimmed
        else { return nil }
        do {
            var environment = ProcessInfo.processInfo.environment
            environment.merge(profile.values) { _, new in new }
            _ = try ProcessRunner.run(
                "/bin/bash", ["-lc", command], environment: environment,
                currentDirectory: profileWorkingDirectory(profile)
            )
            return nil
        } catch {
            return error
        }
    }
}
