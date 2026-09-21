import Foundation

public extension ModelProfileStatus {
    /// Launchable when the agent found all model artifacts (missing_artifacts
    /// empty or absent) or the endpoint is live. Derived here from the wire
    /// facts - the Python agent's `launchable` field was deleted (L08): the
    /// two encodings were provably identical and one owner is enough.
    var isLaunchable: Bool {
        (missingArtifacts?.isEmpty ?? true) || running || ready
    }

    /// Board rows: hide stale flat configs unless the endpoint is still live.
    /// Launch-folder / port claims stay visible so operators can see runners
    /// whose weights are temporarily missing.
    /// Discovery/listening listeners stay off the board: they are not
    /// file-backed, so promoting them to ACTIVE would disagree with the
    /// ready census (`ProfileRuntimeCounts`).
    var isBoardVisible: Bool {
        if isSyntheticDiscoveryProfile {
            return false
        }
        if !isLaunchable {
            if isLaunchFolderClaim {
                return true
            }
            return lifecycle.isActive
        }
        return true
    }
}
