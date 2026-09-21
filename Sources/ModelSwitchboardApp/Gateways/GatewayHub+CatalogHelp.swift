import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    var menuBarHelp: String {
        guard hasRemoteGateways else { return localStore.menuBarHelp }
        return ([localReadyHelp] + remoteReadyHelpParts).joined(separator: " · ")
    }

    var localReadyHelp: String {
        "This Mac: \(localStore.displayedReadyProfiles)/\(localStore.summary.totalProfiles) ready"
    }

    var remoteReadyHelpParts: [String] {
        enabledRemoteRuntimes.map { runtime in
            "\(runtime.name): \(runtime.store.displayedReadyProfiles)/\(runtime.store.summary.totalProfiles) ready"
        }
    }
}
