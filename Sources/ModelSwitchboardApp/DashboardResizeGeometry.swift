import AppKit

enum DashboardResizeEdge {
    case leading
    case trailing
}

struct DashboardResizeGeometry {
    static let edgeHitWidth: CGFloat = 10

    static func resizedFrame(
        from startFrame: NSRect,
        edge: DashboardResizeEdge,
        translationX: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) -> NSRect {
        let rawWidth = switch edge {
        case .leading:
            startFrame.width - translationX
        case .trailing:
            startFrame.width + translationX
        }
        let nextWidth = min(max(rawWidth, minWidth), maxWidth)
        var frame = startFrame
        frame.size.width = nextWidth
        if edge == .leading {
            frame.origin.x = startFrame.maxX - nextWidth
        }
        return frame
    }
}
