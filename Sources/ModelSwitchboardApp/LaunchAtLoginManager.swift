import Foundation
import ServiceManagement
import ModelSwitchboardCore

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var isAvailable = false
    @Published var lastError: String?

    private init() {
        refresh()
    }

    func refresh() {
        guard #available(macOS 13.0, *) else {
            isAvailable = false
            isEnabled = false
            requiresApproval = false
            return
        }

        isAvailable = true
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
        case .notFound, .notRegistered:
            isEnabled = false
            requiresApproval = false
        @unknown default:
            isEnabled = false
            requiresApproval = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }

        do {
            if enabled {
                try unregisterCompanionEditionLoginItem()
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        refresh()
    }

    @available(macOS 13.0, *)
    private func unregisterCompanionEditionLoginItem() throws {
        guard
            let currentBundleIdentifier = Bundle.main.bundleIdentifier,
            let companionBundleIdentifier = LoginItemBundleIdentifiers.companion(for: currentBundleIdentifier)
        else {
            return
        }

        let companionService = SMAppService.loginItem(identifier: companionBundleIdentifier)
        switch companionService.status {
        case .enabled, .requiresApproval:
            try companionService.unregister()
        case .notFound, .notRegistered:
            break
        @unknown default:
            break
        }
    }
}
