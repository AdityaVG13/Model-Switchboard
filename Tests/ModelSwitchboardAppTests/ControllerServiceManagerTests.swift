import Foundation
import Testing
@testable import ModelSwitchboardApp

@MainActor
struct ControllerServiceManagerTests {
    @Test func ensureRegisteredReportsMissingEmbeddedControllerWhenBundleIncomplete() throws {
        let manager = ControllerServiceManager.shared

        // Packaged Xcode hosts may already embed the controller; only assert the
        // incomplete-bundle diagnostic path.
        guard manager.bundledServiceAvailable == false else {
            return
        }

        let diagnostic = try #require(manager.ensureRegistered())
        #expect(diagnostic.localizedCaseInsensitiveContains("missing the embedded controller"))
        #expect(manager.lastDiagnostic == diagnostic)
        #expect(manager.ensureRegistered() == diagnostic)
    }
}
