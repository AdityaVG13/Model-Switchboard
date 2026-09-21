import SwiftUI
import ModelSwitchboardCore

extension RemoteHostsPanelView {
    var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No remote gateways")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.label)
            Text("Add a remote host in Settings to see GPU, VRAM, CPU, and RAM here.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
