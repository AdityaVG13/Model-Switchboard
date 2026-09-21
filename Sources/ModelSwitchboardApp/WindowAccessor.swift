import AppKit
import SwiftUI

/// Resolves the host `NSWindow` and paints a solid backdrop synchronously when
/// the view attaches - before the next display refresh - so MenuBarExtra does
/// not flash clear/black on open.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> HostWindowPaintView {
        let view = HostWindowPaintView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: HostWindowPaintView, context: Context) {
        nsView.onResolve = onResolve
        // Keep backdrop current (theme can change while open).
        if let window = nsView.window {
            MenuBarExtraWindowBackdrop.apply(to: window)
            onResolve(window)
        }
    }
}
