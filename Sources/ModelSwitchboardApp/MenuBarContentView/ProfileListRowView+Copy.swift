import AppKit
import SwiftUI
import ModelSwitchboardCore

extension ProfileListRowView {
    @ViewBuilder
    var copyEndpointButton: some View {
        if showReachability {
            if let reachableEndpointURL {
                Button("Copy Endpoint URL") { copyToPasteboard(reachableEndpointURL) }
            } else {
                Button("Endpoint not reachable from this Mac") {}
                    .disabled(true)
            }
        } else {
            Button("Copy Endpoint URL") { copyToPasteboard(profile.baseURL) }
        }
    }

    func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
