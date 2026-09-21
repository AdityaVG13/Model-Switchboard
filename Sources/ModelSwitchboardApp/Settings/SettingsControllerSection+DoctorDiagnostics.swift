import SwiftUI
import ModelSwitchboardCore

extension SettingsControllerSection {
    @ViewBuilder
    var doctorDiagnostics: some View {
        if profileDiagnostics.isEmpty {
            SettingsFootnote(
                text: "No profile errors or warnings on the latest controller refresh.",
                color: DashboardTheme.runningGreen
            )
        } else {
            ForEach(profileDiagnostics) { diagnostic in
                diagnosticCard(diagnostic)
            }
        }
    }
}
