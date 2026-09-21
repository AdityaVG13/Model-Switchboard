import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var currentPayload: ControllerStatusPayload {
        ControllerStatusPayload(
            statuses: statuses,
            benchmark: benchmark,
            integrations: integrations,
            profilesDirectory: profilesDirectory,
            controllerRoot: controllerRoot
        )
    }

    var summary: DashboardSummary {
        DashboardSummary(counts: ProfileRuntimeCounts(statuses: statuses), benchmark: benchmark)
    }

    var displayedRunningProfiles: Int {
        displayedRunningProfiles(relativeTo: .now)
    }

    var displayedReadyProfiles: Int {
        displayedReadyProfiles(relativeTo: .now)
    }

    var menuBarHelp: String {
        menuBarHelp(relativeTo: .now)
    }
}
