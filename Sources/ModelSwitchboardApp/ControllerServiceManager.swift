import Foundation
import ModelSwitchboardCore
import OSLog
import ServiceManagement

@MainActor
final class ControllerServiceManager {
    static let shared = ControllerServiceManager()
    static let plistName = controllerLaunchAgentPlistName

    static let logger = Logger(
        subsystem: "io.modelswitchboard.app",
        category: "controller-service"
    )

    let bundle: ControllerBundleLayout
    let fileManager: FileManager
    var attemptedRegistration = false
    var didBootstrap = false

    /// Held strongly so the detached fallback `serve` process is not deallocated mid-run
    /// while the LaunchAgent (KeepAlive) or a later relaunch takes long-lived ownership.
    var detachedControllerProcess: Process?

    /// Set when registration cannot start a controller the panel can talk to.
    var lastDiagnostic: String?

    init(bundle: ControllerBundleLayout = .main) {
        self.bundle = bundle
        self.fileManager = bundle.fileManager
    }

    var bundledServiceAvailable: Bool {
        bundle.hasEmbeddedController
    }
}
