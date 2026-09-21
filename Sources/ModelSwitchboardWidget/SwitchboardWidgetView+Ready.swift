import SwiftUI
import WidgetKit
import ModelSwitchboardCore

extension SwitchboardWidgetView {
    var readyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(statuses.prefix(family == .systemSmall ? 2 : 4)), id: \.profile) { profile in
                readyRow(profile)
            }
        }
    }

    var footer: some View {
        HStack {
            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
            Spacer(minLength: 0)
            if family == .systemMedium {
                Button(intent: RefreshSwitchboardWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
        }
    }

    func offlineState(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Controller offline")
                .font(.caption.bold())
            Text(error)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(family == .systemSmall ? 3 : 4)
        }
    }
}
