import AppKit

extension MenuBarExtraWindowBackdrop {
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
}
