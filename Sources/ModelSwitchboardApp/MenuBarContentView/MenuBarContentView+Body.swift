import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var body: some View {
        applyPanelLifecycle(
            mainPanelCard
                .frame(width: mainPanelWidth, height: panelHeight)
                .introspectMenuBarExtraWindow { window in
                    MenuBarExtraWindowBackdrop.apply(to: window)
                    if hostWindow !== window { hostWindow = window }
                    configureHostWindow(window)
                }
                .background(
                    WindowAccessor { window in
                        guard let window else { return }
                        if hostWindow !== window {
                            hostWindow = window
                        }
                        configureHostWindow(window)
                        synchronizeInspectorWindow()
                    }
                )
        )
    }
}
