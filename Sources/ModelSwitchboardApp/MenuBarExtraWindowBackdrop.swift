import AppKit

/// Shared backdrop paint for MenuBarExtra host windows.
@MainActor
enum MenuBarExtraWindowBackdrop {
    static func apply(to window: NSWindow, scheme: ColorSchemeHint? = nil) {
        let resolved = scheme ?? .resolvedFromApp()
        window.isOpaque = true
        window.backgroundColor = backdropColor(for: resolved)
        window.animationBehavior = .utilityWindow
        // Avoid titlebar/traffic-light chrome fighting our card.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }

    enum ColorSchemeHint {
        case light
        case dark

        @MainActor static func resolvedFromApp() -> ColorSchemeHint {
            let appearance = NSApp.effectiveAppearance
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? .dark : .light
        }
    }
}
