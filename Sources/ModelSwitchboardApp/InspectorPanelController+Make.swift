import AppKit
import SwiftUI

extension InspectorPanelController {
    func makePanel(
        content: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> (InspectorPanelWindow, NSHostingView<AnyView>) {
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.autoresizingMask = [.width, .height]

        let window = InspectorPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = true
        window.level = .floating
        window.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        window.becomesKeyOnlyIfNeeded = true

        panelWindow = window
        hostingView = host
        return (window, host)
    }
}
