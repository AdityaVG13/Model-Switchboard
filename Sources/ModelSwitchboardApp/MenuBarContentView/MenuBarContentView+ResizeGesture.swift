import AppKit
import SwiftUI

extension MenuBarContentView {
    func resizeGesture(_ edge: DashboardResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                applyResizeTranslation(value.translation.width, edge: edge)
            }
            .onEnded { _ in
                persistResizedWidth()
            }
    }

    func applyResizeTranslation(_ translationX: CGFloat, edge: DashboardResizeEdge) {
        guard let hostWindow else { return }
        let startFrame = activeResizeStartFrame ?? hostWindow.frame
        if activeResizeStartFrame == nil {
            activeResizeStartFrame = startFrame
        }
        let nextFrame = DashboardResizeGeometry.resizedFrame(
            from: startFrame,
            edge: edge,
            translationX: translationX,
            minWidth: minMainPanelWidth,
            maxWidth: maxMainPanelWidth
        )
        hostWindow.setFrame(nextFrame, display: true)
        synchronizeInspectorWindow()
    }
}
