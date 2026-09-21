import SwiftUI
import ModelSwitchboardCore

extension ActiveProfileHeroView {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                heroIdentity
                Spacer(minLength: 0)
                trailingMetric
            }

            heroActions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.13), accent.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 0, trailing: 10))
    }
}
