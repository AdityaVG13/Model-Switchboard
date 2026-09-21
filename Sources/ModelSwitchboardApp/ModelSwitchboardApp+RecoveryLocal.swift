import SwiftUI
import AppKit
import ModelSwitchboardCore

extension ModelSwitchboardApp {
    /// Bootstrap diagnostics concern the local LaunchAgent only;
    /// remote gateway stores must never inherit them.
    func recoverLocalController() async {
        let diagnostic = await ControllerServiceManager.shared.ensureRegistered()
        store.applyBootstrapDiagnostic(diagnostic)
        // Auto-refresh already fired from store init, often before the
        // LaunchAgent is listening after a crash/reboot. Poll again
        // once registration has had a chance to bring the port up.
        if diagnostic == nil {
            await store.refresh(includeDoctor: true)
        }
    }
}
