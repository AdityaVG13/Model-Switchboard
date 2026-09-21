import AppKit
import SwiftUI

extension InspectorPanelController {
    func fadeInIfNeeded(_ window: InspectorPanelWindow) {
        window.alphaValue = 1
        if !window.isVisible {
            window.alphaValue = showAnimationDuration > 0 ? 0 : 1
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = showAnimationDuration
                window.animator().alphaValue = 1
            }
        } else {
            window.orderFront(nil)
        }
    }
}
