import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var resolvedControllerRoot: String? {
        // Only ever reveal the canonical, app-owned controller root. Trusting an arbitrary
        // value reported by the running controller (which may be a stray/dev install with the
        // same launch-agent label) is how a second, unexpected folder can surface.
        let canonicalRoot = controllerRootToReveal.path
        guard FileManager.default.fileExists(atPath: canonicalRoot) else { return nil }
        return canonicalRoot
    }

    var resolvedExampleProfilesDirectory: String? {
        for target in [
            profilesDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent("examples").path },
            resolvedControllerRoot.map { URL(fileURLWithPath: $0).appendingPathComponent("model-profiles/examples").path },
        ].compactMap({ $0 }) where FileManager.default.fileExists(atPath: target) {
            return target
        }
        return nil
    }
}
