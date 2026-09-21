import SwiftUI
import WidgetKit
import ModelSwitchboardCore

extension SwitchboardWidgetView {
    func readyRow(_ profile: ModelProfileStatus) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(profile.ready ? Color.green : (profile.running ? Color.orange : Color.gray))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(profile.stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
    }
}
