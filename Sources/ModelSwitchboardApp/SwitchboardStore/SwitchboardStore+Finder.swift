import AppKit
import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func openProfilesDirectory() {
        let url = profilesDirectoryToReveal
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        seedBundledExampleProfilesIfNeeded(in: url)
        revealInFinder(url)
    }

    func openControllerRoot() {
        let url = controllerRootToReveal
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        revealInFinder(url)
    }

    func openExampleProfilesDirectory() {
        let profiles = profilesDirectoryToReveal
        try? FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        seedBundledExampleProfilesIfNeeded(in: profiles)
        let examples = exampleProfilesDirectoryToReveal
        if FileManager.default.fileExists(atPath: examples.path) {
            revealInFinder(examples)
        } else {
            revealInFinder(profiles)
        }
    }
}
