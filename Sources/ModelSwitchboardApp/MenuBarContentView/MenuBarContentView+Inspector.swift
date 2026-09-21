import AppKit
import SwiftUI

extension MenuBarContentView {
    func inspectorCard(_ panel: InspectorPanel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text(panel.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.label)
                inspectorCloseButton(panel)
            }
            .padding(EdgeInsets(top: 12, leading: DashboardChromeMetrics.inspectorChromeInset(), bottom: 12, trailing: DashboardChromeMetrics.inspectorChromeInset()))
            panelDivider

            inspectorView(panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: inspectorPanelWidth, height: panelHeight, alignment: .topLeading)
        .background(theme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: DashboardChromeMetrics.continuousCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DashboardChromeMetrics.continuousCornerRadius, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .preferredColorScheme(resolvedColorScheme)
    }
}
