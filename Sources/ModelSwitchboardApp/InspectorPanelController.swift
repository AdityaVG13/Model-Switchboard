import AppKit
import SwiftUI

@MainActor
final class InspectorPanelController {
    var panelWindow: InspectorPanelWindow?
    var hostingView: NSHostingView<AnyView>?
    weak var parentWindow: NSWindow?
    let showAnimationDuration: TimeInterval
    let hideAnimationDuration: TimeInterval
    var visibilityGeneration = 0

    init(
        showAnimationDuration: TimeInterval = 0.16,
        hideAnimationDuration: TimeInterval = 0.14
    ) {
        self.showAnimationDuration = showAnimationDuration
        self.hideAnimationDuration = hideAnimationDuration
    }
}
