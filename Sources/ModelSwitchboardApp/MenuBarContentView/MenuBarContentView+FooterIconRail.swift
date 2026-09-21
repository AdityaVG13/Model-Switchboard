import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footerIconRail: some View {
        HStack(spacing: 2) {
            footerIconButton("questionmark.circle", label: "Help") {
                let nextPanel = inspectorCoordinator.toggle(.help)
                synchronizeInspectorWindow(panel: nextPanel)
            }
            if hub.hasRemoteGateways {
                footerIconButton("server.rack", label: "Remote Hosts") {
                    let nextPanel = inspectorCoordinator.toggle(.remoteHosts)
                    synchronizeInspectorWindow(panel: nextPanel)
                }
            }
            footerIconButton("gearshape", label: "Settings") {
                let nextPanel = inspectorCoordinator.toggle(.settings)
                synchronizeInspectorWindow(panel: nextPanel)
            }
            footerIconButton("power", label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .layoutPriority(1)
    }
}
