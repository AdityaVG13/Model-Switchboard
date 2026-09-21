import AppKit
import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Reveals a folder in Finder and brings Finder to the front. `NSWorkspace.open(_:)`
    /// launches Finder but leaves it behind the app; `activateFileViewerSelecting` reveals
    /// the item in a focused window, fixing the "folder opens behind the app" behaviour.
    func revealInFinder(_ url: URL) {
        let directory = (url.pathExtension.isEmpty || hasDirectoryPath(url))
            ? url
            : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func hasDirectoryPath(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
