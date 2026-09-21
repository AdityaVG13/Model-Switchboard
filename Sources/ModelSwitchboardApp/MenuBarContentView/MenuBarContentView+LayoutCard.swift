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
}
