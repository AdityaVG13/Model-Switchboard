import AppKit
import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func openProfilesDirectory() {
        guard let profilesDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: profilesDirectory))
    }

    func openControllerRoot() {
        guard let target = resolvedControllerRoot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    func openExampleProfilesDirectory() {
        guard let target = resolvedExampleProfilesDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    var resolvedControllerRoot: String? {
        if let controllerRoot, !controllerRoot.isEmpty {
            return controllerRoot
        }

        guard let profilesDirectory, !profilesDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: profilesDirectory)
            .deletingLastPathComponent()
            .path
    }

    var resolvedExampleProfilesDirectory: String? {
        let preferredTargets = [
            profilesDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent("examples").path },
            resolvedControllerRoot.map { URL(fileURLWithPath: $0).appendingPathComponent("model-profiles/examples").path },
        ]

        for target in preferredTargets.compactMap({ $0 }) where FileManager.default.fileExists(atPath: target) {
            return target
        }
        return nil
    }
}
