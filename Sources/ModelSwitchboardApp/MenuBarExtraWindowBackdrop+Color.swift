import AppKit

extension MenuBarExtraWindowBackdrop {
    static func backdropColor(for scheme: ColorSchemeHint) -> NSColor {
        switch scheme {
        case .light:
            return NSColor(srgbRed: 246 / 255, green: 246 / 255, blue: 248 / 255, alpha: 1)
        case .dark:
            // Match DashboardTheme.dark.panelBg (26,26,29).
            return NSColor(srgbRed: 26 / 255, green: 26 / 255, blue: 29 / 255, alpha: 1)
        }
    }
}
