import AppKit
import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// First-run Finder open should include the example templates the docs tell
    /// people to copy. Bootstrap usually seeds them; this covers the race
    /// where Open Profiles Folder runs before the LaunchAgent copy finishes.
    func seedBundledExampleProfilesIfNeeded(in profiles: URL) {
        let examples = profiles.appendingPathComponent("examples", isDirectory: true)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: examples.path) else { return }
        guard
            let bundled = Bundle.main.resourceURL?
                .appendingPathComponent("ControllerSupport/model-profiles/examples", isDirectory: true),
            fileManager.fileExists(atPath: bundled.path)
        else { return }
        try? fileManager.copyItem(at: bundled, to: examples)
    }
}
