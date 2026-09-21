import SwiftUI
import ModelSwitchboardCore

extension HelpView {
    var helpSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(title: "Quick Start", bullets: quickStartBullets)
            section(title: "Remote Gateways", bullets: remoteGatewayBullets)
            section(title: "Profile Setup", bullets: profileSetupBullets)
            section(title: "Good Operating Discipline", bullets: operatingDisciplineBullets)
            section(title: "Troubleshooting", bullets: troubleshootingBullets)
            exampleProfilesSection
            section(title: "Power User Extras", bullets: powerUserBullets)
        }
    }
}
