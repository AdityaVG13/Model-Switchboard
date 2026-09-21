import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerServiceManager {
    func bootstrapSupportDirectory() throws {
        guard let source = bundle.controllerSupportURL else { return }
        let destination = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ModelSwitchboard/Controller", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for script in ["start-model-mac.sh", "stop-all-models.sh"] {
            try replaceExecutable(script, from: source, to: destination)
        }
        let profiles = destination.appendingPathComponent("model-profiles", isDirectory: true)
        try fileManager.createDirectory(at: profiles, withIntermediateDirectories: true)
        try migrateLegacyProfilesIfNeeded(to: profiles)
        try copyExamplesIfMissing(from: source, to: profiles)
    }

    func replaceExecutable(_ name: String, from source: URL, to destination: URL) throws {
        let sourceFile = source.appendingPathComponent(name)
        let destinationFile = destination.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destinationFile.path) {
            try fileManager.removeItem(at: destinationFile)
        }
        try fileManager.copyItem(at: sourceFile, to: destinationFile)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationFile.path)
    }

    func copyExamplesIfMissing(from source: URL, to profiles: URL) throws {
        let examplesSource = source.appendingPathComponent("model-profiles/examples", isDirectory: true)
        let examplesDestination = profiles.appendingPathComponent("examples", isDirectory: true)
        if !fileManager.fileExists(atPath: examplesDestination.path),
            fileManager.fileExists(atPath: examplesSource.path)
        {
            try fileManager.copyItem(at: examplesSource, to: examplesDestination)
        }
    }
}
