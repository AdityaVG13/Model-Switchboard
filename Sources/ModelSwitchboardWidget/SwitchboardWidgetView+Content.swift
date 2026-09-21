import SwiftUI
import WidgetKit
import ModelSwitchboardCore

extension SwitchboardWidgetView {
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(features.appDisplayName)
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold, design: .rounded))
                Text(modeTitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 8)
            Image(systemName: summary.menuBarSystemImage)
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold))
                .foregroundStyle(.mint)
        }
    }

    @ViewBuilder
    var content: some View {
        switch displayMode {
        case .summary:
            summaryContent
        case .readyFirst:
            readyContent
        }
    }
}
