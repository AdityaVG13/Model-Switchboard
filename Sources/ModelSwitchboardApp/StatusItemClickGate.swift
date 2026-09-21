import AppKit

/// Rate-limits clicks on the MenuBarExtra status item so spam-tapping the
/// menu bar icon cannot thrash the window open/closed (which flashes black
/// through the transparent MenuBarExtra host).
@MainActor
final class StatusItemClickGate {
    /// Minimum interval between accepted status-item toggles.
    var minimumToggleInterval: TimeInterval = 0.45

    weak var statusItem: NSStatusItem?
    var monitor: Any?
    var lastAcceptedToggleAt: Date = .distantPast

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
}
