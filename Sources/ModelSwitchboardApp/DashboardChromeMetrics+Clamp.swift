import CoreGraphics
import Foundation

extension DashboardChromeMetrics {
    static func clampPanelWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, minMainPanelWidth), maxMainPanelWidth)
    }

    static func clampPanelWidth(_ value: Double) -> Double {
        Double(clampPanelWidth(CGFloat(value)))
    }
}
