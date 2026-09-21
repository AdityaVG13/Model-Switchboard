import AppKit

extension StatusItemClickGate {
    func filterStatusItemClick(_ event: NSEvent) -> NSEvent? {
        guard hitsStatusItemButton(event) else { return event }
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

    func hitsStatusItemButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return false
        }
        guard event.window === buttonWindow else { return false }
        let locationInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(locationInButton)
    }
}
