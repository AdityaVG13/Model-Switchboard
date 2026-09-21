import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    var heroIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isBusy ? DashboardTheme.pendingOrange : DashboardTheme.runningGreen)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(accent)
            }
            Text(profile.displayName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(theme.label)
            Text(subtitle)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.sub)
                .lineLimit(1)
                .truncationMode(.middle)
                .modifier(LocalURLSelection(enabled: showsURLSelection))
        }
    }
}
