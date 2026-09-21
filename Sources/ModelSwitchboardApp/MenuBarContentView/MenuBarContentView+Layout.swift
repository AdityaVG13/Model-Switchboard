import AppKit
import SwiftUI

extension MenuBarContentView {
    var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            panelDivider
            if let error = localPanelError {
                errorBanner(error)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    modelListSection
                    remoteGatewaySections
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            panelDivider
            footer
        }
    }

    var panelDivider: some View {
        theme.line.frame(height: 1)
    }
}
