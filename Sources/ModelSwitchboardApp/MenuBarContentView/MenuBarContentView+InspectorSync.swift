import AppKit
import SwiftUI

extension MenuBarContentView {
    func synchronizeInspectorWindow(
        panel: InspectorPanel? = nil
    ) {
        guard let hostWindow else { return }
        let currentPanel = panel ?? inspectorCoordinator.openPanel
        guard let currentPanel else {
            // Never re-key the host window on hide - that re-opens/focuses the
            // menu bar dashboard when the user already clicked away.
            inspectorController.hide()
            return
        }

        inspectorController.show(
            title: currentPanel.title,
            parent: hostWindow,
            width: inspectorPanelWidth,
            height: panelHeight,
            gap: panelGap,
            // Menu bar sits on the right; always open the inspector to the left
            // of the dashboard (flips only if the left edge of the screen blocks it).
            side: .leading,
            // Settings needs SecureField key focus; other panels must not steal
            // activation or the MenuBarExtra stays stuck when clicking outside.
            allowsKeyFocus: currentPanel == .settings,
            content: AnyView(inspectorCard(currentPanel))
        )
    }
}
