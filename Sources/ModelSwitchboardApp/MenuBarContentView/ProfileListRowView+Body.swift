import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            identityColumn

            HStack(spacing: 4) {
                primaryButton
                rowMenu
            }
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
        .contentShape(Rectangle())
        .background(RowHoverHighlight(color: theme.hoverBg))
    }
}
