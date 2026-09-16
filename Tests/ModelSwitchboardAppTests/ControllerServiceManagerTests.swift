import Foundation
import Testing
@testable import ModelSwitchboardApp

@MainActor
struct ControllerServiceManagerTests {
    @Test func ensureRegisteredReportsMissingEmbeddedControllerForIncompleteBundle() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ControllerServiceManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ControllerServiceManager(
            bundle: ControllerBundleLayout(
                resourceURL: tempRoot.appendingPathComponent("Resources", isDirectory: true),
                bundleURL: tempRoot
            )
        )

        #expect(manager.bundledServiceAvailable == false)
        let diagnostic = try #require(await manager.ensureRegistered())
        #expect(diagnostic.localizedCaseInsensitiveContains("missing the embedded controller"))
        #expect(manager.lastDiagnostic == diagnostic)
        // Repeated calls must keep reporting; a one-shot flag used to hide this
        // after the first LaunchAgent / Login Items failure.
        #expect(await manager.ensureRegistered() == diagnostic)
        #expect(await manager.ensureRegistered() == diagnostic)
    }
}
