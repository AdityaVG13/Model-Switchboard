import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func activate(_ profile: String) async {
        await runProfileAction(profile, label: .activating) {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.activate(profile: profile)
        }
    }

    func start(_ profile: String) async {
        await runProfileAction(profile, label: .starting) {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.start(profile: profile)
        }
    }
}
