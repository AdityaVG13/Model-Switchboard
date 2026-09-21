import SwiftUI
import ModelSwitchboardCore

extension HelpView {
    func section(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(theme.faint)
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(theme.faint)
                    Text(bullet)
                        .font(.footnote)
                        .foregroundStyle(theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
