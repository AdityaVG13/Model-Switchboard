import AppKit
import SwiftUI

extension MenuBarContentView {
    /// Local-only banner. Remote gateway errors render in their section so a
    /// downed Mac controller does not paint the whole multi-gateway panel red.
    var localPanelError: String? {
        guard let error = store.lastError, !error.isEmpty else { return nil }
        if hub.hasRemoteGateways, store.sortedStatuses.isEmpty {
            return nil
        }
        return error
    }

    func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(DashboardTheme.stopRed)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
    }
}
