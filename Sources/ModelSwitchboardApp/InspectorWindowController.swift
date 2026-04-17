import AppKit
import SwiftUI

@MainActor
final class InspectorWindowController {
    private let panelSize = NSSize(width: 290, height: 620)
    private let panelGap: CGFloat = 10

    private weak var hostWindow: NSWindow?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    func present<Content: View>(
        title: String,
        from hostWindow: NSWindow,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.hostWindow = hostWindow

        let panel = makePanelIfNeeded()
        panel.title = title
        panel.contentView = nil

        let rootView = InspectorPanelChrome(title: title, onClose: onClose, content: AnyView(content()))
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
        self.hostingView = hostingView

        if panel.parent !== hostWindow {
            panel.parent?.removeChildWindow(panel)
            hostWindow.addChildWindow(panel, ordered: .above)
        }

        position(panel: panel, relativeTo: hostWindow)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func repositionIfNeeded() {
        guard let panel, let hostWindow else { return }
        position(panel: panel, relativeTo: hostWindow)
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, relativeTo hostWindow: NSWindow) {
        let anchorFrame = hostWindow.frame
        let screenFrame = hostWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorFrame

        var originX = anchorFrame.minX - panelSize.width - panelGap
        if originX < screenFrame.minX + 8 {
            originX = min(anchorFrame.maxX + panelGap, screenFrame.maxX - panelSize.width - 8)
        }

        let maxY = min(anchorFrame.maxY, screenFrame.maxY - 8)
        var originY = maxY - panelSize.height
        originY = max(screenFrame.minY + 8, originY)

        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize), display: true)
    }
}

private struct InspectorPanelChrome: View {
    let title: String
    let onClose: () -> Void
    let content: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(title)")
            }

            content

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 290, height: 620, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}
