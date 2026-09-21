import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func stop(_ profile: String) async {
        await runProfileAction(profile, label: .stopping) {
            markProfile(profile, running: false, ready: false)
        } action: {
            try await $0.stop(profile: profile)
        } verify: {
            try await self.verifyProfileStopped(profile, using: $0)
        }
    }

    func restart(_ profile: String) async {
        await runProfileAction(profile, label: .restarting) {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.restart(profile: profile)
        }
    }

    func setProfilesDirectory(_ path: String) async {
        _ = await run(
            { try await $0.setProfilesDirectory(path) },
            actionName: "Save profiles folder"
        )
    }
}
