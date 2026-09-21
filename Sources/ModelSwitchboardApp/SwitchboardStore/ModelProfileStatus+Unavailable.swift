import Foundation
import ModelSwitchboardCore

extension ModelProfileStatus {
    /// `updating(...)` treats nil as "keep current value", so it cannot clear
    /// pid/rssMB. A dead endpoint must drop them explicitly.
    func markingEndpointUnavailable() -> Self {
        Self(
            profile: profile,
            displayName: displayName,
            runtime: runtime,
            runtimeLabel: runtimeLabel,
            runtimeTags: runtimeTags,
            launchMode: launchMode,
            host: host,
            port: port,
            baseURL: baseURL,
            requestModel: requestModel,
            serverModelID: serverModelID,
            pid: nil,
            running: false,
            ready: false,
            serverIDs: [],
            rssMB: nil,
            command: command,
            logPath: logPath
        )
    }
}
