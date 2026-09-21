import AppKit
import SwiftUI

extension InspectorPanelController {
    func panelAndHost(
        content: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> (InspectorPanelWindow, NSHostingView<AnyView>) {
        if let existingWindow = panelWindow, let existingHost = hostingView {
            return (existingWindow, existingHost)
        }
        return makePanel(content: content, width: width, height: height)
    }
}
