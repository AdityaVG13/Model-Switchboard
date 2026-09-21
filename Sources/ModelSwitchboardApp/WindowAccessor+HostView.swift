import AppKit
import SwiftUI

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
