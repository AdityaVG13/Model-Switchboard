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
                // MenuBarExtra maps the label to a status-item title: only the
                // first Text survives (verified: trailing segments vanish, and
                // baselineOffset is dropped), so the fraction must be one
                // string. U+2215 DIVISION SLASH stays inside the digit band
                // (measured: vertically centered @2x), unlike "/" which sags
                // ~5px below the digits; hair spaces restore the air its
                // narrow bearings remove.
                Text("\(hub.displayedReadyProfiles)\u{200A}\u{2215}\u{200A}\(hub.totalProfiles)")
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
