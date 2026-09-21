import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footer: some View {
        HStack(alignment: .center, spacing: 0) {
            footerActions
            footerFreshnessChip
            footerIconRail
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.leading, DashboardChromeMetrics.continuousCornerSafeInset)
        .padding(.trailing, DashboardChromeMetrics.footerTrailingInset())
    }
}
