import Foundation
import ServiceManagement

@MainActor
final class ControllerServiceManager {
    static let shared = ControllerServiceManager()
    static let plistName = "io.modelswitchboard.controller.plist"

    private let fileManager = FileManager.default
    private var attemptedRegistration = false

    private init() {}

    func ensureRegistered() {
        guard !attemptedRegistration, bundledServiceAvailable else { return }
        attemptedRegistration = true
        do {
            try bootstrapSupportDirectory()
            removeLegacyLaunchAgent()
            let service = SMAppService.agent(plistName: Self.plistName)
            if service.status == .notRegistered {
                try service.register()
            }
        } catch {
            NSLog("Model Switchboard controller registration failed: %@", error.localizedDescription)
        }
    }

    private var bundledServiceAvailable: Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        return fileManager.isExecutableFile(atPath: resources.appendingPathComponent("ModelSwitchboardController").path)
            && fileManager.fileExists(atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LaunchAgents/\(Self.plistName)").path)
    }

    private func bootstrapSupportDirectory() throws {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("ControllerSupport", isDirectory: true),
              fileManager.fileExists(atPath: source.path) else { return }
        let destination = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ModelSwitchboard/Controller", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for script in ["start-model-mac.sh", "stop-all-models.sh"] {
            let sourceFile = source.appendingPathComponent(script)
            let destinationFile = destination.appendingPathComponent(script)
            if fileManager.fileExists(atPath: destinationFile.path) { try fileManager.removeItem(at: destinationFile) }
            try fileManager.copyItem(at: sourceFile, to: destinationFile)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationFile.path)
        }
        let profiles = destination.appendingPathComponent("model-profiles", isDirectory: true)
        try fileManager.createDirectory(at: profiles, withIntermediateDirectories: true)
        try migrateLegacyProfilesIfNeeded(to: profiles)
        let examplesSource = source.appendingPathComponent("model-profiles/examples", isDirectory: true)
        let examplesDestination = profiles.appendingPathComponent("examples", isDirectory: true)
        if !fileManager.fileExists(atPath: examplesDestination.path), fileManager.fileExists(atPath: examplesSource.path) {
            try fileManager.copyItem(at: examplesSource, to: examplesDestination)
        }
    }

    private func migrateLegacyProfilesIfNeeded(to destination: URL) throws {
        let activeProfiles = try fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .filter { ["env", "json"].contains($0.pathExtension.lowercased()) }
        guard activeProfiles.isEmpty else { return }
        let cache = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/io.modelswitchboard/controller-status.json")
        guard let data = try? Data(contentsOf: cache),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let payload = object["payload"] as? [String: Any] ?? object
        guard
              let root = payload["controller_root"] as? String else { return }
        let legacyProfiles = URL(fileURLWithPath: root).appendingPathComponent("model-profiles", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyProfiles.path) else { return }
        for source in try fileManager.contentsOfDirectory(at: legacyProfiles, includingPropertiesForKeys: nil)
            where ["env", "json"].contains(source.pathExtension.lowercased()) {
            try fileManager.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
        }
    }

    private func removeLegacyLaunchAgent() {
        let legacy = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/io.modelswitchboard.controller.plist")
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", legacy.path]
        try? process.run()
        process.waitUntilExit()
        try? fileManager.removeItem(at: legacy)
    }
}
