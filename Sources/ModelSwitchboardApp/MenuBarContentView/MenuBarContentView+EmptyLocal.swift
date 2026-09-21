import Foundation
import ModelSwitchboardCore

extension MenuBarContentView {
    static func localOnlyEmptyCopy(
        lastError: String?,
        profilesDirectory: String?,
        isRecovering: Bool
    ) -> String {
        if lastError != nil {
            if isRecovering {
                return "The local controller is still starting."
            }
            return "No model profiles reported yet. Check the controller connection in Settings."
        }
        if let dir = profilesDirectory.nonEmptyTrimmed {
            return "No model profiles in \(dir). Copy an example from the examples folder into that folder, fill in your model path, and Refresh."
        }
        return "No model profiles yet. Open Settings → Open Profiles Folder, copy an example, fill in your model path, then Refresh."
    }
}
