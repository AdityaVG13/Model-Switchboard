import AppKit
import CoreGraphics
import Testing
@testable import ModelSwitchboardApp

@Test func clampPanelWidthEnforcesShippedMinimum() {
    #expect(DashboardChromeMetrics.clampPanelWidth(372 as CGFloat) == DashboardChromeMetrics.minMainPanelWidth)
    #expect(DashboardChromeMetrics.clampPanelWidth(399 as CGFloat) == 400)
    #expect(DashboardChromeMetrics.clampPanelWidth(400 as CGFloat) == 400)
    #expect(DashboardChromeMetrics.clampPanelWidth(500 as CGFloat) == 500)
    #expect(DashboardChromeMetrics.clampPanelWidth(900 as CGFloat) == DashboardChromeMetrics.maxMainPanelWidth)
    #expect(DashboardChromeMetrics.clampPanelWidth(300.0) == 400.0)
}

@Test func continuousCornerSafeInsetCoversCornerRadius() {
    // Content inset must be >= continuous corner radius or glyphs clip.
    #expect(DashboardChromeMetrics.continuousCornerSafeInset >= DashboardChromeMetrics.continuousCornerRadius)
    #expect(DashboardChromeMetrics.footerTrailingInset() >= DashboardChromeMetrics.continuousCornerRadius)
    #expect(DashboardChromeMetrics.inspectorChromeInset() >= DashboardChromeMetrics.continuousCornerRadius)
}

@Test func canStopAnythingIsQuietWhenIdle() {
    #expect(
        DashboardChromeMetrics.canStopAnything(
            isBusy: false,
            storesHaveRunning: false,
            storesHavePending: false
        ) == false
    )
}

@Test func canStopAnythingTrueWhenRunningOrPendingOrBusy() {
    #expect(
        DashboardChromeMetrics.canStopAnything(
            isBusy: false,
            storesHaveRunning: true,
            storesHavePending: false
        )
    )
    #expect(
        DashboardChromeMetrics.canStopAnything(
            isBusy: false,
            storesHaveRunning: false,
            storesHavePending: true
        )
    )
    #expect(
        DashboardChromeMetrics.canStopAnything(
            isBusy: true,
            storesHaveRunning: false,
            storesHavePending: false
        )
    )
}

@Test func footerIconRailFitsInsideMinPanelWithSafeInsets() {
    // Dense footer must fit: leading inset + rail + trailing inset <= min width.
    // Three icons with hit size and 2pt gaps, plus safe insets both sides.
    let rail =
        3 * DashboardChromeMetrics.footerIconHitSize
        + 2 * 2 // spacing between three icons
    let chrome =
        DashboardChromeMetrics.continuousCornerSafeInset
        + rail
        + DashboardChromeMetrics.footerTrailingInset()
    #expect(chrome < DashboardChromeMetrics.minMainPanelWidth)
    // Leave room for at least ~180pt of left labels (Benchmarks / Sync / Stop).
    #expect(DashboardChromeMetrics.minMainPanelWidth - chrome >= 180)
}

@Test func resizeGeometryUsesCompatibleMinWidthWithChrome() {
    // Shipped min panel width must be accepted by resize clamp path.
    let start = NSRect(x: 100, y: 100, width: 500, height: DashboardChromeMetrics.panelHeight)
    let clamped = DashboardResizeGeometry.resizedFrame(
        from: start,
        edge: .trailing,
        translationX: -200,
        minWidth: DashboardChromeMetrics.minMainPanelWidth,
        maxWidth: DashboardChromeMetrics.maxMainPanelWidth
    )
    #expect(clamped.width == DashboardChromeMetrics.minMainPanelWidth)
}
