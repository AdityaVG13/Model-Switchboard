import SwiftUI
import WidgetKit
import ModelSwitchboardCore

extension SwitchboardWidgetView {
    var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                metric(title: "Ready", value: "\(summary.readyProfiles)/\(summary.totalProfiles)")
                metric(title: "Running", value: "\(summary.runningProfiles)")
            }
            if let first = statuses.first {
                Text(first.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(first.stateDescription)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
    }

    func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: family == .systemSmall ? 18 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var modeTitle: String {
        switch displayMode {
        case .summary:
            return "Summary"
        case .readyFirst:
            return "Ready models"
        }
    }
}
