import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var identityColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(profile.displayName)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(theme.label)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.sub)
                .lineLimit(1)
            if let endpointLine {
                Text(endpointLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }
}
