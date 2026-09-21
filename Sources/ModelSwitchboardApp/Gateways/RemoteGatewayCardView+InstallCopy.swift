import AppKit
import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewayCardView {
    var copyInstallCommandRow: some View {
        HStack(spacing: 8) {
            Text(RemoteAgentInstallCopy.oneLiner)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.faint)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(RemoteAgentInstallCopy.oneLiner, forType: .string)
                didCopyInstallCommand = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    didCopyInstallCommand = false
                }
            } label: {
                Image(systemName: didCopyInstallCommand ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(didCopyInstallCommand ? DashboardTheme.runningGreen : accent)
                    .frame(width: 28, height: 28)
                    .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(didCopyInstallCommand ? "Copied" : "Copy install command")
            .accessibilityLabel(didCopyInstallCommand ? "Copied install command" : "Copy install command")
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 6))
        .background(theme.panelBg.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
