import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    func metricTile(label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(theme.sub)
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(accent)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.system(size: 9.5))
                    .hidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
        .background(theme.panelBg.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RemoteHostsPresentation.metricAccessibilityLabel(
            label: label,
            value: value,
            detail: detail
        ))
    }
}
