import AppKit
import SwiftUI

extension MenuBarContentView {
    var mainPanelCard: some View {
        mainPanel
            .frame(width: mainPanelWidth, height: panelHeight, alignment: .topLeading)
            .background(theme.panelBg)
            // continuous clip can nibble monospaced header digits on the leading edge
            // if subviews draw flush against x=0; keep a hair of internal inset.
            .clipShape(RoundedRectangle(cornerRadius: DashboardChromeMetrics.continuousCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DashboardChromeMetrics.continuousCornerRadius, style: .continuous)
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
            if let error = localPanelError {
                errorBanner(error)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    modelListSection
                    remoteGatewaySections
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            panelDivider
            footer
        }
    }

    var panelDivider: some View {
        theme.line.frame(height: 1)
    }

    /// Local-only banner. Remote gateway errors render in their section so a
    /// downed Mac controller does not paint the whole multi-gateway panel red.
    var localPanelError: String? {
        guard let error = store.lastError, !error.isEmpty else { return nil }
        if hub.hasRemoteGateways, store.sortedStatuses.isEmpty {
            return nil
        }
        return error
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
                hostWindow.setFrame(nextFrame, display: true)
                synchronizeInspectorWindow()
            }
            .onEnded { _ in
                // Persist while activeResizeStartFrame is still set so onChange skips
                // setContentSize (which would undo leading-edge origin updates).
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
        DashboardChromeMetrics.clampPanelWidth(value)
    }

    func configureHostWindow(_ window: NSWindow) {
        // Custom edge handles own horizontal resize; native .resizable fights leading-edge pinning.
        window.styleMask.remove(.resizable)
        window.showsResizeIndicator = false
        window.minSize = NSSize(width: minMainPanelWidth, height: panelHeight)
        window.maxSize = NSSize(width: maxMainPanelWidth, height: panelHeight)
        // Solid backdrop so open/close thrash never shows clear/black chrome.
        let scheme: MenuBarExtraWindowBackdrop.ColorSchemeHint =
            resolvedColorScheme == .light ? .light : .dark
        MenuBarExtraWindowBackdrop.apply(to: window, scheme: scheme)
    }
}
