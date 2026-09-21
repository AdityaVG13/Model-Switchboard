import Foundation
import ServiceManagement

extension ControllerServiceManager {
    static let missingBundledControllerMessage =
        "This app build is missing the embedded controller. Reinstall with Scripts/install.sh (or the DMG) so ModelSwitchboardController and its LaunchAgent are present."

    func markMissingBundledController() -> String {
        lastDiagnostic = Self.missingBundledControllerMessage
        Self.logger.error("\(Self.missingBundledControllerMessage, privacy: .public)")
        return lastDiagnostic ?? Self.missingBundledControllerMessage
    }
}
