import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func applyStoredWidth(_ newValue: Double) {
        let clamped = clampPanelWidth(newValue)
        if abs(clamped - newValue) > .ulpOfOne {
            storedMainPanelWidth = clamped
            return
        }
        // While dragging (and during the end-of-drag AppStorage write), skip
        // setContentSize -- it pins the leading edge and undoes origin updates.
        if activeResizeStartFrame != nil { return }
        applyHostWindowWidth(clamped)
        synchronizeInspectorWindow()
    }

    func applyHostWindowWidth(_ clamped: Double) {
        guard let hostWindow else { return }
        let nextWidth = CGFloat(clamped)
        if abs(hostWindow.frame.width - nextWidth) > 0.5, !hostWindow.inLiveResize {
            hostWindow.setContentSize(NSSize(width: nextWidth, height: panelHeight))
        }
    }
}
