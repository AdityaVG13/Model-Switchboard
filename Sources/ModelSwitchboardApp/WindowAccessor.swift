import AppKit
import SwiftUI

/// Resolves the host `NSWindow` and paints a solid backdrop synchronously when
/// the view attaches — before the next display refresh — so MenuBarExtra does
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

final class HostWindowPaintView: NSView {
    var onResolve: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            MenuBarExtraWindowBackdrop.apply(to: window)
        }
        // Call synchronously first so configureHostWindow runs before paint.
        onResolve?(window)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let window {
            MenuBarExtraWindowBackdrop.apply(to: window)
        }
    }
}
