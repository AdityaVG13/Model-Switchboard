import Foundation
import ModelSwitchboardCore

extension MenuBarContentView {
    var localEmptyMessage: String {
        Self.localEmptyCopy(
            hasVisibleStatuses: !store.sortedStatuses.isEmpty,
            hasRemoteGateways: hub.hasRemoteGateways,
            lastError: store.lastError,
            profilesDirectory: store.profilesDirectory,
            isRecovering: store.isRecoveringFromTransportFailure
        )
    }

    /// First-run / empty-board copy. A healthy controller with no profiles is not
    /// a connection failure.
    static func localEmptyCopy(
        hasVisibleStatuses: Bool,
        hasRemoteGateways: Bool,
        lastError: String?,
        profilesDirectory: String?,
        isRecovering: Bool = false
    ) -> String {
        if hasVisibleStatuses {
            return "No models match this filter."
        }
        if hasRemoteGateways {
            return remoteOnlyEmptyCopy(lastError: lastError)
        }
        return localOnlyEmptyCopy(
            lastError: lastError,
            profilesDirectory: profilesDirectory,
            isRecovering: isRecovering
        )
    }
}
