import AppKit
import SwiftUI

enum InspectorPanelSide {
    case leading
    case trailing
}

@MainActor
final class InspectorPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
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

    func show(
        title: String,
        parent: NSWindow,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        side: InspectorPanelSide = .leading,
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
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.transient, .moveToActiveSpace]

            panelWindow = window
            hostingView = host
        }

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

        let frame = NSRect(
            x: Self.panelOriginX(
                parentFrame: parent.frame,
                screenVisibleFrame: parent.screen?.visibleFrame,
                width: width,
                gap: gap,
                side: side
            ),
            y: parent.frame.minY,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true)
        window.alphaValue = 1
        if !window.isVisible {
            window.alphaValue = showAnimationDuration > 0 ? 0 : 1
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = showAnimationDuration
                window.animator().alphaValue = 1
            }
        } else {
            window.orderFront(nil)
        }
    }

    /// Resolves the panel's x origin for the requested side, flipping to the
    /// opposite side when the preferred placement would leave the visible screen.
    nonisolated static func panelOriginX(
        parentFrame: NSRect,
        screenVisibleFrame: NSRect?,
        width: CGFloat,
        gap: CGFloat,
        side: InspectorPanelSide
    ) -> CGFloat {
        let leadingX = parentFrame.minX - gap - width
        let trailingX = parentFrame.maxX + gap

        guard let screen = screenVisibleFrame else {
            return side == .leading ? leadingX : trailingX
        }

        switch side {
        case .leading:
            return leadingX >= screen.minX ? leadingX : trailingX
        case .trailing:
            return trailingX + width <= screen.maxX ? trailingX : leadingX
        }
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
