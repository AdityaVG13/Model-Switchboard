import SwiftUI
import ModelSwitchboardCore

extension SettingsAppearanceSection {
    var accentSwatches: some View {
        HStack(spacing: 6) {
            ForEach(DashboardAccent.allCases, id: \.rawValue) { choice in
                Button {
                    accentRaw = choice.rawValue
                } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 18, height: 18)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .stroke(
                                    choice.rawValue == accentRaw ? theme.label : .clear,
                                    lineWidth: 2
                                )
                                .frame(width: 24, height: 24)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietCraftPressStyle())
                .accessibilityLabel("\(choice.rawValue) accent")
                .accessibilityAddTraits(choice.rawValue == accentRaw ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
