import SwiftUI
import AppKit
import ModelSwitchboardCore

extension ModelSwitchboardApp {
    func saveDebouncedToken(_ newValue: String) async {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let trimmed = newValue.trimmed
        // Debounced empty save clears the keychain so an intentional
        // clear/rotate-to-no-auth sticks across relaunch.
        KeychainTokenStorage.shared.save(trimmed)
        store.controllerAuthToken = newValue
        await store.refresh(includeDoctor: true)
    }
}
