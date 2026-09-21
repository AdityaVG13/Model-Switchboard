import AppKit
import SwiftUI

extension InspectorPanelController {
    /// - Parameter allowsKeyFocus: true for Settings (SecureField); false for
    ///   Remote Hosts / Benchmarks / Help so the panel does not steal key focus
    ///   and pin the MenuBarExtra open when the user clicks elsewhere.
    func show(
        title: String,
        parent: NSWindow,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        side: InspectorPanelSide = .leading,
        allowsKeyFocus: Bool = false,
        content: AnyView
    ) {
        visibilityGeneration += 1
        let (window, host) = panelAndHost(content: content, width: width, height: height)

        window.allowsKeyFocus = allowsKeyFocus
        host.rootView = content
        window.title = title
        window.setContentSize(NSSize(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        attachPanel(window, to: parent)
        placePanel(window, parent: parent, width: width, height: height, gap: gap, side: side)
        fadeInIfNeeded(window)
    }
}
