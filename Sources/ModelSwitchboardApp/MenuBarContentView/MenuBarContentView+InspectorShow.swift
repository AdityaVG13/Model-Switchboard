import AppKit
import SwiftUI

extension MenuBarContentView {
    func setInspectorPanel(_ nextPanel: InspectorPanel?) {
        if nextPanel == inspectorCoordinator.openPanel,
            inspectorCoordinator.deferredClosePanel != nextPanel {
            return
        }
        _ = withAnimation(inspectorAnimation) {
            inspectorCoordinator.show(nextPanel)
        }
        synchronizeInspectorWindow(panel: nextPanel)
    }
}
