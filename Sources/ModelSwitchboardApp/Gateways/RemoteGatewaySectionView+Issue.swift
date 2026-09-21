import SwiftUI
import ModelSwitchboardCore

extension RemoteGatewaySectionView {
    @ViewBuilder
    var connectionIssueLabel: some View {
        if let issue = connectionIssue {
            Text(issue)
                .font(.system(size: 10.5))
                .foregroundStyle(DashboardTheme.pendingOrange)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 4))
        }
    }
}
