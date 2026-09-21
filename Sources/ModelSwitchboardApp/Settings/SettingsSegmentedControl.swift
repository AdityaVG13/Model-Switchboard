import SwiftUI

struct SettingsSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option
    let theme: DashboardTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = selection == option
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(minHeight: 24)
                        .background(
                            isOn ? theme.tabOnBg : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .foregroundStyle(isOn ? theme.tabOnFg : theme.tabOffFg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietCraftPressStyle())
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
