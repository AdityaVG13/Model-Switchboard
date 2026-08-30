import AppKit

/// Rate-limits clicks on the MenuBarExtra status item so spam-tapping the
/// menu bar icon cannot thrash the window open/closed (which flashes black
/// through the transparent MenuBarExtra host).
@MainActor
final class StatusItemClickGate {
    /// Minimum interval between accepted status-item toggles.
    var minimumToggleInterval: TimeInterval = 0.45

    private weak var statusItem: NSStatusItem?
    private var monitor: Any?
    private var lastAcceptedToggleAt: Date = .distantPast

    func attach(to item: NSStatusItem) {
        statusItem = item
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self else { return event }
                return self.filterStatusItemClick(event)
            }
        }
        // Solid backdrop as soon as we know about the window (may still be nil).
        if let window = MenuBarExtraWindowBackdrop.menuBarExtraWindow(for: item) {
            MenuBarExtraWindowBackdrop.apply(to: window)
        }
    }

    func detach() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        statusItem = nil
    }


    private func filterStatusItemClick(_ event: NSEvent) -> NSEvent? {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return event
        }
        // Only filter clicks that hit this status item's button.
        guard event.window === buttonWindow else { return event }
        let locationInButton = button.convert(event.locationInWindow, from: nil)
        guard button.bounds.contains(locationInButton) else { return event }

        let now = Date()
        if now.timeIntervalSince(lastAcceptedToggleAt) < minimumToggleInterval {
            // Swallow - leaves the panel in its current open/closed state.
            return nil
        }
        lastAcceptedToggleAt = now

        // Paint the host window *before* the toggle so the first frame is not clear.
        if let host = MenuBarExtraWindowBackdrop.menuBarExtraWindow(for: statusItem) {
            MenuBarExtraWindowBackdrop.apply(to: host)
        }
        return event
    }
}

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

    static func menuBarExtraWindow(for statusItem: NSStatusItem?) -> NSWindow? {
        // Prefer the dedicated MenuBarExtra content window over the status bar chrome.
        let hosts = NSApp.windows.filter { $0.className.contains("MenuBarExtraWindow") }
        if hosts.count == 1 { return hosts[0] }
        if let statusItem {
            return hosts.first { window in
                // Best-effort association; often only one extra is present.
                _ = statusItem
                return true
            } ?? hosts.first
        }
        return hosts.first
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
