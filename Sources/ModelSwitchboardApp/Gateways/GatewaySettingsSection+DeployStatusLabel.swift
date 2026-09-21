import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func deployStatusLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(color)
    }
}
