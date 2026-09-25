import SwiftUI
import AppKit
import ModelSwitchboardCore
import MenuBarExtraAccess

extension ModelSwitchboardApp {
    var menuBarLabel: some View {
        HStack(spacing: 3) {
            LeverSwitchIcon(
                hasReadyModels: hub.displayedReadyProfiles > 0,
                hasRunningModels: hub.displayedRunningProfiles > 0,
                size: 18
            )
            if menuBarShowsReadyCount {
                Text("\(hub.displayedReadyProfiles)/\(hub.totalProfiles)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        }
        .task {
            statusItem?.button?.toolTip = hub.menuBarHelp
            await recoverLocalController()
        }
        .onChange(of: hub.menuBarHelp) { _, newValue in
            statusItem?.button?.toolTip = newValue
        }
        .onChange(of: menuBarShowsReadyCount) { _, newValue in
            statusItem?.length = newValue ? NSStatusItem.variableLength : NSStatusItem.squareLength
        }
    }

    func attachStatusItem(_ item: NSStatusItem) {
        statusItem = item
        item.length = menuBarShowsReadyCount ? NSStatusItem.variableLength : NSStatusItem.squareLength
        item.button?.toolTip = hub.menuBarHelp
        // Let SwiftUI own button contents; clearing title / forcing imageOnly
        // clips the ready-count onto neighboring menu bar items.
        item.button?.setAccessibilityLabel("Model Switchboard")
        // Rate-limit spam clicks on the menu bar icon (black-flash thrash).
        statusItemClickGate.attach(to: item)
    }
}
