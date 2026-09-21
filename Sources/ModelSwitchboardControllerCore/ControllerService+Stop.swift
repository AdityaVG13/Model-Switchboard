import Foundation
import ModelSwitchboardCore

extension ControllerService {
    public func stop(_ name: String) throws {
        try withMutationLock {
            suppressWatchdog()
            clearActiveProfile(ifMatching: name)
            let profile = try profiles.profile(named: name)
            let currentStatus = status(for: profile)
            let primaryPID = trustedStopPID(name: name, profile: profile, current: currentStatus)
            let stopError = runStopCommand(profile)
            try stopOwnedProcesses(profile: profile, name: name, primaryPID: primaryPID)
            try? fileManager.removeItem(at: pidFile(name))
            if let stopError {
                throw ControllerError.operationFailed("STOP_COMMAND failed for \(name): \(stopError)")
            }
        }
    }

    func requireExistingProfile(_ name: String, action: String) throws -> [String: ControllerProfile] {
        let loaded = try profiles.load()
        guard loaded[name] != nil else { throw ControllerError.profileNotFound(name) }
        try profiles.ensureUnique(name, action: action, profiles: loaded)
        return loaded
    }

    func stopOwnedProcesses(profile: ControllerProfile, name: String, primaryPID: Int?) throws {
        if EnvFlag.isEnabled(profile["STOP_COMMAND_ONLY"]) { return }
        terminateProfileProcesses(profile, primaryPID: primaryPID)
        if waitUntilStopped(profile, primaryPID: primaryPID) { return }
        terminateProfileProcesses(profile, primaryPID: primaryPID)
        guard waitUntilStopped(profile, primaryPID: primaryPID, timeout: 24) else {
            throw ControllerError.operationFailed(
                "failed to stop \(name): endpoint or process is still alive")
        }
    }
}
