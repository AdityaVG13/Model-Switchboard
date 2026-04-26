import AppKit
import Testing
@testable import ModelSwitchboardApp

@Test func leadingResizeKeepsTrailingEdgePinned() {
    let start = NSRect(x: 400, y: 120, width: 470, height: 620)

    let expanded = DashboardResizeGeometry.resizedFrame(
        from: start,
        edge: .leading,
        translationX: -80,
        minWidth: 390,
        maxWidth: 620
    )

    #expect(expanded.width == 550)
    #expect(expanded.maxX == start.maxX)
    #expect(expanded.minX == 320)
}

@Test func leadingResizeClampsWidthWithoutMovingTrailingEdge() {
    let start = NSRect(x: 400, y: 120, width: 470, height: 620)

    let clamped = DashboardResizeGeometry.resizedFrame(
        from: start,
        edge: .leading,
        translationX: 200,
        minWidth: 390,
        maxWidth: 620
    )

    #expect(clamped.width == 390)
    #expect(clamped.maxX == start.maxX)
    #expect(clamped.minX == 480)
}

@Test func trailingResizeKeepsLeadingEdgePinned() {
    let start = NSRect(x: 400, y: 120, width: 470, height: 620)

    let expanded = DashboardResizeGeometry.resizedFrame(
        from: start,
        edge: .trailing,
        translationX: 80,
        minWidth: 390,
        maxWidth: 620
    )

    #expect(expanded.width == 550)
    #expect(expanded.minX == start.minX)
    #expect(expanded.maxX == 950)
}
