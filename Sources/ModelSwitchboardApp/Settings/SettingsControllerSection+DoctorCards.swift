import SwiftUI
import ModelSwitchboardCore

extension SettingsControllerSection {
    func diagnosticCard(_ diagnostic: ProfileDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diagnostic.displayName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.label)
            ForEach(diagnostic.errors, id: \.self) { error in
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.stopRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(diagnostic.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.pendingOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(diagnostic.baseURL)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.sub)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.hoverBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
