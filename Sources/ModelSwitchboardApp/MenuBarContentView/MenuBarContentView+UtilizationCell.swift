import SwiftUI

extension MenuBarContentView {
    func utilizationCell(
        label: String,
        value: Double?,
        history: [Double],
        helpText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 9.5))
                    .kerning(0.4)
                    .foregroundStyle(theme.sub)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.label)
            }
            utilizationSparkline(history)
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9))
        .frame(maxWidth: .infinity)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(utilizationAccessibilityLabel(label: label, value: value))
        .modifier(OptionalHelp(text: utilizationHelp(label: label, value: value, helpText: helpText)))
    }
}
