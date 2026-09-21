import AppKit
import SwiftUI

extension MenuBarContentView {
    func inspectorCloseButton(_ panel: InspectorPanel) -> some View {
        HStack {
            Button {
                inspectorCoordinator.requestDeferredClose(of: panel)
                DispatchQueue.main.async {
                    let nextPanel = inspectorCoordinator.commitDeferredClose(of: panel)
                    synchronizeInspectorWindow(panel: nextPanel)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Close")
                        .font(.system(size: 12, weight: .medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(QuietCraftPressStyle())
            .foregroundStyle(accent)
            .accessibilityLabel("Close \(panel.title)")
            Spacer()
        }
    }
}
