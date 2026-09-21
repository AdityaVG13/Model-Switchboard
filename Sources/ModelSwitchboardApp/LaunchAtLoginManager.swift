import Foundation
import OSLog
import ServiceManagement
import ModelSwitchboardCore

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    static let logger = Logger(
        subsystem: "io.modelswitchboard.app",
        category: "login-item"
    )

    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var isAvailable = false
    @Published var lastError: String?

    private init() {
        refresh()
    }

    func refresh() {
        guard #available(macOS 13.0, *) else {
            markUnavailable()
            return
        }

        isAvailable = true
        (isEnabled, requiresApproval) = Self.flags(from: SMAppService.mainApp.status)
    }

    func markUnavailable() {
        isAvailable = false
        isEnabled = false
        requiresApproval = false
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        applyLoginItem(enabled)
        refresh()
    }
}
