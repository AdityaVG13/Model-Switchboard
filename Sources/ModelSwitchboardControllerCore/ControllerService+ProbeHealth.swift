import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func probeHealth(_ profile: ControllerProfile) -> (ready: Bool, serverIDs: [String]) {
        guard profile.healthcheckMode != "disabled", let url = URL(string: profile.healthcheckURL),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return (false, []) }
        let remoteAllowed = EnvFlag.isEnabled(
            ProcessInfo.processInfo.environment["ALLOW_REMOTE_HEALTHCHECK"])
        guard remoteAllowed || ControllerConfiguration.isLoopback(url.host ?? "") else {
            return (false, [])
        }
        guard
            let result = try? ProcessRunner.run(
                "/usr/bin/curl",
                [
                    "--fail", "--silent", "--show-error",
                    "--max-redirs", "0",
                    "--noproxy", "*",
                    "--max-time", "1.5", "--header",
                    "Accept: application/json", url.absoluteString,
                ]
            )
        else { return (false, []) }
        if profile.healthcheckMode == "http-200" { return (true, []) }
        return decodeOpenAIModelIDs(stdout: result.stdout, profile: profile)
    }
}
