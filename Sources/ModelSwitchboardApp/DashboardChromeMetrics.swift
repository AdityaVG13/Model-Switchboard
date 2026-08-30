import CoreGraphics
import Foundation

/// Layout constants and pure rules for menu-bar chrome so continuous-corner
/// clips, dense footers, and idle stop affordances stay honest without a
/// visual redesign.
enum DashboardChromeMetrics {
    /// Matches `RoundedRectangle(cornerRadius:style: .continuous)` on panels.
    static let continuousCornerRadius: CGFloat = 12

    /// Minimum distance from panel edge to interactive glyphs so continuous
    /// corners do not nibble labels or trailing icons (Apple craft: deliberate inset).
    static let continuousCornerSafeInset: CGFloat = 14

    static let footerIconHitSize: CGFloat = 26
    static let minMainPanelWidth: CGFloat = 400
    static let maxMainPanelWidth: CGFloat = 620
    static let inspectorPanelWidth: CGFloat = 372
    static let panelHeight: CGFloat = 620

    static func clampPanelWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, minMainPanelWidth), maxMainPanelWidth)
    }

    static func clampPanelWidth(_ value: Double) -> Double {
        Double(clampPanelWidth(CGFloat(value)))
    }

    /// Idle stop affordance: enabled only when something is running or a stop
    /// is already in flight (quiet disabled state when idle).
    static func canStopAnything(
        isBusy: Bool,
        storesHaveRunning: Bool,
        storesHavePending: Bool
    ) -> Bool {
        if isBusy { return true }
        return storesHaveRunning || storesHavePending
    }

    /// Trailing padding for a fixed icon rail so the last icon stays fully
    /// inside the continuous corner (hit size is square; glyph is centered).
    static func footerTrailingInset() -> CGFloat {
        continuousCornerSafeInset
    }

    /// Leading/trailing content inset for inspector headers under continuous clip.
    static func inspectorChromeInset() -> CGFloat {
        continuousCornerSafeInset
    }
}
