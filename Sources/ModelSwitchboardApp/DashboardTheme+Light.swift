import SwiftUI

extension DashboardTheme {
    /// Light mode tuned for WCAG-ish contrast on model rows (image #2 failure).
    static let light = DashboardTheme(
        panelBg: srgb(244, 244, 247),
        cellBg: srgb(255, 255, 255),
        hoverBg: srgb(232, 232, 237),
        line: srgb(210, 210, 216),
        label: srgb(28, 28, 30),
        sub: srgb(72, 72, 78),
        faint: srgb(100, 100, 108),
        btnBg: srgb(228, 228, 234),
        btnFg: srgb(40, 40, 46),
        btnStrongBg: srgb(214, 214, 220),
        btnStrongFg: srgb(22, 22, 24),
        tabOnBg: srgb(255, 255, 255),
        tabOnFg: srgb(22, 22, 24),
        tabOffFg: srgb(90, 90, 98),
        dotOff: srgb(150, 150, 158),
        sparkStroke: srgb(120, 120, 128),
        panelBorder: srgb(200, 200, 208),
        fieldBg: srgb(255, 255, 255),
        fieldFg: srgb(28, 28, 30)
    )
}
