import SwiftUI
import ModelSwitchboardCore

extension SettingsControllerSection {
    func doctorSummary(_ report: DoctorReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                report.controller.reachable ? "Controller reachable" : "Controller unreachable",
                systemImage: report.controller.reachable ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(report.controller.reachable ? DashboardTheme.runningGreen : DashboardTheme.stopRed)

            Label(
                report.launchAgent.running ? "Launch agent running" : "Launch agent not running",
                systemImage: report.launchAgent.running ? "bolt.circle.fill" : "bolt.slash.circle.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(report.launchAgent.running ? DashboardTheme.runningGreen : DashboardTheme.pendingOrange)

            Text(report.controller.url)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.sub)
                .textSelection(.enabled)
        }
    }
}
