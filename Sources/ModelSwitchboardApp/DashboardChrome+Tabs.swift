import SwiftUI

extension DashboardSegmentedTabs {
    func tabButton(_ option: Option) -> some View {
        let isOn = option == selection
        return Button {
            guard option != selection else { return }
            if reduceMotion {
                selection = option
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    selection = option
                }
            }
        } label: {
            Text(label(option))
                .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .frame(minHeight: 24)
                .foregroundStyle(isOn ? theme.tabOnFg : theme.tabOffFg)
                .contentShape(Rectangle())
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.tabOnBg)
                            .matchedGeometryEffect(id: "selected-tab", in: tabChipNamespace)
                    }
                }
        }
        .buttonStyle(QuietCraftPressStyle())
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
