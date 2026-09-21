import SwiftUI
import AppKit
import ModelSwitchboardCore

extension ModelSwitchboardApp {
    func handleTokenChange(_ newValue: String) {
        // Debounced: this fires per keystroke while typing a token.
        tokenSaveTask?.cancel()
        tokenSaveTask = Task { await saveDebouncedToken(newValue) }
    }
}
