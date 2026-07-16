import AppKit
import SwiftUI

extension MenuBarContentView {
    var mainPanelCard: some View {
        mainPanel
            .frame(width: mainPanelWidth, height: panelHeight)
            .background(theme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.panelBorder, lineWidth: 1)
            }
            .overlay {
                HStack(spacing: 0) {
                    resizeHandle(.leading)
                    Spacer(minLength: 0)
                    resizeHandle(.trailing)
                }
            }
    }

    var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            panelDivider
            if let error = store.lastError {
                errorBanner(error)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    modelListSection
                }
            }
            .frame(maxHeight: .infinity)
            panelDivider
            footer
        }
    }

    var panelDivider: some View {
        theme.line.frame(height: 1)
    }

    func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(DashboardTheme.stopRed)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
    }

    func resizeHandle(_ edge: DashboardResizeEdge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: DashboardResizeGeometry.edgeHitWidth)
            .contentShape(Rectangle())
            .gesture(resizeGesture(edge))
            .help("Resize dashboard")
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    func resizeGesture(_ edge: DashboardResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard let hostWindow else { return }
                let startFrame = activeResizeStartFrame ?? hostWindow.frame
                if activeResizeStartFrame == nil {
                    activeResizeStartFrame = startFrame
                }
                let nextFrame = DashboardResizeGeometry.resizedFrame(
                    from: startFrame,
                    edge: edge,
                    translationX: value.translation.width,
                    minWidth: minMainPanelWidth,
                    maxWidth: maxMainPanelWidth
                )
                // Apply the full frame (including origin) during the drag. Persisting
                // width into AppStorage mid-drag used to trigger setContentSize, which
                // pins the leading edge and makes a left-handle drag look like a right resize.
                hostWindow.setFrame(nextFrame, display: true)
                synchronizeInspectorWindow()
            }
            .onEnded { _ in
                if let hostWindow {
                    let nextWidth = Double(hostWindow.frame.width)
                    if abs(storedMainPanelWidth - nextWidth) > 0.5 {
                        storedMainPanelWidth = nextWidth
                    }
                }
                activeResizeStartFrame = nil
                synchronizeInspectorWindow()
            }
    }

    func clampPanelWidth(_ value: Double) -> Double {
        min(max(value, minMainPanelWidth), maxMainPanelWidth)
    }

    func configureHostWindow(_ window: NSWindow) {
        // Edge handles own horizontal resize. Native .resizable grows from the
        // opposite edge and fights leading-handle pinning under MenuBarExtra.
        window.styleMask.remove(.resizable)
        window.showsResizeIndicator = false
        window.minSize = NSSize(width: minMainPanelWidth, height: panelHeight)
        window.maxSize = NSSize(width: maxMainPanelWidth, height: panelHeight)
    }
}
