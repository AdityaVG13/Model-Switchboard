import AppKit

extension InspectorPanelController {
    /// Resolves the panel's x origin for the requested side, flipping to the
    /// opposite side when the preferred placement would leave the visible screen.
    /// Does not move the parent - keeps a true side-by-side child panel.
    nonisolated static func panelOriginX(
        parentFrame: NSRect,
        screenVisibleFrame: NSRect?,
        width: CGFloat,
        height: CGFloat = 0,
        gap: CGFloat,
        side: InspectorPanelSide
    ) -> CGFloat {
        let leadingX = parentFrame.minX - gap - width
        let trailingX = parentFrame.maxX + gap

        guard let screen = screenVisibleFrame else {
            return side == .leading ? leadingX : trailingX
        }

        switch side {
        case .leading:
            return leadingX >= screen.minX ? leadingX : trailingX
        case .trailing:
            return trailingX + width <= screen.maxX ? trailingX : leadingX
        }
    }
}
