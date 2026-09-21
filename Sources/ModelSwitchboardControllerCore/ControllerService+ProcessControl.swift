import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func terminateProfileProcesses(_ profile: ControllerProfile, primaryPID: Int?) {
        if let primaryPID { ProcessRunner.terminate(primaryPID) }
        if let listener = listenerPID(port: profile.endpointPort), listener != primaryPID,
            processMatches(listener, profile: profile)
        {
            ProcessRunner.terminate(listener)
        }
    }

    func waitUntilStopped(
        _ profile: ControllerProfile, primaryPID: Int?, timeout: TimeInterval = 90
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let listener = listenerPID(port: profile.endpointPort)
            let listenerAlive =
                listener.map { $0 == primaryPID || processMatches($0, profile: profile) } ?? false
            if !ProcessRunner.processIsAlive(primaryPID), !listenerAlive { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    func suppressWatchdog() { watchdogSuppressedUntil = Date().addingTimeInterval(45) }

    func clearActiveProfile(ifMatching name: String) {
        guard
            let current = try? String(contentsOf: configuration.activeProfileFile, encoding: .utf8)
                .trimmed, current == name
        else { return }
        try? fileManager.removeItem(at: configuration.activeProfileFile)
    }
}
