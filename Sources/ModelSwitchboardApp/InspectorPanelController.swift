import AppKit
import SwiftUI

enum InspectorPanelSide {
    case leading
    case trailing
}

@MainActor
final class InspectorPanelWindow: NSPanel {
    /// Settings needs typing; display panels stay non-activating so click-out
    /// of the menu bar dashboard can dismiss without focus thrash.
    var allowsKeyFocus = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class InspectorPanelController {
    private var panelWindow: InspectorPanelWindow?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?
    private let showAnimationDuration: TimeInterval
    private let hideAnimationDuration: TimeInterval
    private var visibilityGeneration = 0

    init(
        showAnimationDuration: TimeInterval = 0.16,
        hideAnimationDuration: TimeInterval = 0.14
    ) {
        self.showAnimationDuration = showAnimationDuration
        self.hideAnimationDuration = hideAnimationDuration
    }

    /// - Parameter allowsKeyFocus: true for Settings (SecureField); false for
    ///   Remote Hosts / Benchmarks / Help so the panel does not steal key focus
    ///   and pin the MenuBarExtra open when the user clicks elsewhere.
    func show(
        title: String,
        parent: NSWindow,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        side: InspectorPanelSide = .leading,
        allowsKeyFocus: Bool = false,
        content: AnyView
    ) {
        visibilityGeneration += 1
        let window: InspectorPanelWindow
        let host: NSHostingView<AnyView>

        if let existingWindow = panelWindow, let existingHost = hostingView {
            window = existingWindow
            host = existingHost
        } else {
            host = NSHostingView(rootView: content)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.autoresizingMask = [.width, .height]

            window = InspectorPanelWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovable = false
            window.isMovableByWindowBackground = false
            // Follow parent deactivate so click-outside dismisses the pair.
            window.hidesOnDeactivate = true
            window.level = .floating
            window.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
            // Do not take app activation away from the user's current focus.
            window.becomesKeyOnlyIfNeeded = true

            panelWindow = window
            hostingView = host
        }

        window.allowsKeyFocus = allowsKeyFocus
        host.rootView = content
        window.title = title
        window.setContentSize(NSSize(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let isAttachedToParent = parent.childWindows?.contains(where: { $0 === window }) == true
        if parentWindow !== parent || !isAttachedToParent {
            parentWindow?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
            parentWindow = parent
        }

        // Honor Left/Right relative to the dashboard. Menu bar windows often sit
        // on the right edge; when "Right" would go off-screen, shift the parent
        // left so the inspector can still open on the preferred side instead of
        // silently flipping (which made "Right" look inverted).
        let layout = Self.layoutFrames(
            parentFrame: parent.frame,
            screenVisibleFrame: parent.screen?.visibleFrame,
            panelWidth: width,
            panelHeight: height,
            gap: gap,
            side: side
        )
        if abs(layout.parentFrame.origin.x - parent.frame.origin.x) > 0.5
            || abs(layout.parentFrame.origin.y - parent.frame.origin.y) > 0.5
        {
            parent.setFrame(layout.parentFrame, display: true)
        }

        window.setFrame(layout.panelFrame, display: true)
        window.alphaValue = 1
        if !window.isVisible {
            window.alphaValue = showAnimationDuration > 0 ? 0 : 1
            // Never makeKey — avoids focus thrash that re-activates the menu bar window.
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = showAnimationDuration
                window.animator().alphaValue = 1
            }
        } else {
            window.orderFront(nil)
        }
    }

    /// Panel x for the preferred side, flipping only when the pair cannot fit
    /// on that side even after shifting the parent.
    ///
    /// Kept for unit tests and callers that only need the panel origin.
    nonisolated static func panelOriginX(
        parentFrame: NSRect,
        screenVisibleFrame: NSRect?,
        width: CGFloat,
        height: CGFloat = 0,
        gap: CGFloat,
        side: InspectorPanelSide
    ) -> CGFloat {
        layoutFrames(
            parentFrame: parentFrame,
            screenVisibleFrame: screenVisibleFrame,
            panelWidth: width,
            panelHeight: height > 0 ? height : parentFrame.height,
            gap: gap,
            side: side
        ).panelFrame.minX
    }

    /// Returns parent + panel frames that honor `side` when possible.
    nonisolated static func layoutFrames(
        parentFrame: NSRect,
        screenVisibleFrame: NSRect?,
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        gap: CGFloat,
        side: InspectorPanelSide
    ) -> (parentFrame: NSRect, panelFrame: NSRect) {
        let screen = screenVisibleFrame ?? parentFrame
        let pairWidth = parentFrame.width + gap + panelWidth
        var parent = parentFrame
        let height = panelHeight > 0 ? panelHeight : parentFrame.height

        func panelFrame(beside parent: NSRect, side: InspectorPanelSide) -> NSRect {
            let x: CGFloat
            switch side {
            case .leading:
                x = parent.minX - gap - panelWidth
            case .trailing:
                x = parent.maxX + gap
            }
            return NSRect(x: x, y: parent.minY, width: panelWidth, height: height)
        }

        func fits(_ frame: NSRect) -> Bool {
            frame.minX >= screen.minX - 0.5 && frame.maxX <= screen.maxX + 0.5
        }

        // 1) Preferred side beside the current parent.
        var panel = panelFrame(beside: parent, side: side)
        if fits(panel) {
            return (parent, panel)
        }

        // 2) Shift parent so the preferred side fits (typical: Right near screen edge).
        if pairWidth <= screen.width + 0.5 {
            switch side {
            case .trailing:
                // Panel wants the right of parent; park panel against screen right, parent left of it.
                let panelX = screen.maxX - panelWidth
                let parentX = panelX - gap - parent.width
                if parentX >= screen.minX - 0.5 {
                    parent.origin.x = parentX
                    panel = NSRect(x: panelX, y: parent.minY, width: panelWidth, height: height)
                    return (parent, panel)
                }
            case .leading:
                // Panel wants the left of parent; park panel against screen left, parent right of it.
                let panelX = screen.minX
                let parentX = panelX + panelWidth + gap
                if parentX + parent.width <= screen.maxX + 0.5 {
                    parent.origin.x = parentX
                    panel = NSRect(x: panelX, y: parent.minY, width: panelWidth, height: height)
                    return (parent, panel)
                }
            }
        }

        // 3) Last resort: opposite side (may still clip on tiny screens).
        let flipped: InspectorPanelSide = side == .leading ? .trailing : .leading
        panel = panelFrame(beside: parent, side: flipped)
        if fits(panel) {
            return (parent, panel)
        }
        // Clamp panel into the screen as a final fallback.
        var clamped = panel
        if clamped.minX < screen.minX { clamped.origin.x = screen.minX }
        if clamped.maxX > screen.maxX { clamped.origin.x = screen.maxX - panelWidth }
        return (parent, clamped)
    }

    func hide(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let window = panelWindow else {
            completion?()
            return
        }
        visibilityGeneration += 1
        let hideGeneration = visibilityGeneration

        NSAnimationContext.runAnimationGroup { context in
            context.duration = hideAnimationDuration
            window.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                guard hideGeneration == self.visibilityGeneration else { return }
                self.parentWindow?.removeChildWindow(window)
                self.parentWindow = nil
                window.orderOut(nil)
                window.alphaValue = 1
                completion?()
            }
        }
    }
}
