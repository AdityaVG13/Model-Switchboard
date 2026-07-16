import Foundation
import Testing
@testable import ModelSwitchboardApp

@MainActor
struct ControllerServiceManagerTests {
    @Test func ensureRegisteredReportsMissingEmbeddedControllerWhenBundleIncomplete() {
        let manager = ControllerServiceManager.shared

        // Xcode hosts may be a fully packaged .app (controller present) or a bare
        // test runner (controller absent). Only assert the incomplete-bundle path.
        guard manager.bundledServiceAvailable == false else {
            return
        }

        let diagnostic = manager.ensureRegistered()
        #expect(diagnostic != nil)
        #expect(diagnostic!.localizedCaseInsensitiveContains("missing the embedded controller"))
        #expect(manager.lastDiagnostic == diagnostic)
        #expect(manager.ensureRegistered() == diagnostic)
    }
}
