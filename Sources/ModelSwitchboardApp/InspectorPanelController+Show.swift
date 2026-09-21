import AppKit
import SwiftUI

extension InspectorPanelController {
    func attachPanel(_ window: InspectorPanelWindow, to parent: NSWindow) {
        let isAttachedToParent = parent.childWindows?.contains(where: { $0 === window }) == true
        if parentWindow !== parent || !isAttachedToParent {
            parentWindow?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
            parentWindow = parent
        }
    }

    func placePanel(
        _ window: InspectorPanelWindow,
        parent: NSWindow,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        side: InspectorPanelSide
    ) {
        let originX = Self.panelOriginX(
            parentFrame: parent.frame,
            screenVisibleFrame: parent.screen?.visibleFrame,
            width: width,
            gap: gap,
            side: side
        )
        window.setFrame(
            NSRect(x: originX, y: parent.frame.minY, width: width, height: height),
            display: true
        )
    }
}
