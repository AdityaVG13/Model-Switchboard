import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

extension ModelSwitchboardApp {
    func applyMenuBarContentLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                applyControllerBindings()
            }
            .onChange(of: controllerBaseURL) { _, newValue in
                store.controllerBaseURL = newValue
                Task { await store.refresh(includeDoctor: true) }
            }
            .onChange(of: controllerAuthToken) { _, newValue in
                handleTokenChange(newValue)
            }
    }
}
