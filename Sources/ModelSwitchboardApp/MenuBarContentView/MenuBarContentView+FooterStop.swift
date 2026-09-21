import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var footerStopButton: some View {
        footerTextButton(
            stopButtonTitle,
            color: hasAnythingToStop ? DashboardTheme.stopRed : theme.faint,
            isBusy: hub.isStopEverythingBusy,
            disabled: !hasAnythingToStop,
            holdToConfirm: true,
            holdHelpDetail: stopButtonHelp
        ) {
            Task { await hub.stopEverything() }
        }
    }
}
