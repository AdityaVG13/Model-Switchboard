import Foundation
import ModelSwitchboardCore
import OSLog
import ServiceManagement

@MainActor
final class ControllerServiceManager {
    static let shared = ControllerServiceManager()
    static let plistName = "io.modelswitchboard.controller.plist"

    private static let logger = Logger(
        subsystem: "io.modelswitchboard.app",
        category: "controller-service"
    )

    private let fileManager = FileManager.default
    private var attemptedRegistration = false

    /// Set when registration cannot start a controller the panel can talk to.
    private(set) var lastDiagnostic: String?

    private init() {}

    @discardableResult
    func ensureRegistered() -> String? {
        guard !attemptedRegistration else { return lastDiagnostic }
        attemptedRegistration = true
        lastDiagnostic = nil

        guard bundledServiceAvailable else {
            let message =
                "This app build is missing the embedded controller. Reinstall with Scripts/install.sh (or the DMG) so ModelSwitchboardController and its LaunchAgent are present."
            lastDiagnostic = message
            Self.logger.error("\(message, privacy: .public)")
            return lastDiagnostic
        }

        do {
            try bootstrapSupportDirectory()
            removeLegacyLaunchAgent()
            let service = SMAppService.agent(plistName: Self.plistName)
            if service.status == .notRegistered {
                try service.register()
            }
            // Don't block App.init waiting for the port. If the LaunchAgent is not
            // enabled yet, start a detached serve and let SwitchboardStore refresh.
            if service.status != .enabled {
                launchDetachedControllerIfNeeded()
            }
            if service.status == .notFound {
                lastDiagnostic =
                    "Controller LaunchAgent was not found in this app bundle. Reinstall Model Switchboard so the embedded controller can register."
            }
        } catch {
            let message = "Controller registration failed: \(error.localizedDescription)"
            Self.logger.error("\(message, privacy: .public)")
            launchDetachedControllerIfNeeded()
            lastDiagnostic = message
        }
        return lastDiagnostic
    }

    var bundledServiceAvailable: Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        return fileManager.isExecutableFile(atPath: resources.appendingPathComponent("ModelSwitchboardController").path)
            && fileManager.fileExists(atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LaunchAgents/\(Self.plistName)").path)
    }

    private func launchDetachedControllerIfNeeded() {
        guard let binary = Bundle.main.resourceURL?.appendingPathComponent("ModelSwitchboardController"),
              fileManager.isExecutableFile(atPath: binary.path) else { return }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        do {
            try process.run()
            Self.logger.info("Launched detached controller (pid \(process.processIdentifier))")
        } catch {
            Self.logger.error(
                "Detached controller launch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
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
        let activeProfiles = try profileFiles(in: destination)
        guard activeProfiles.isEmpty else { return }

        for legacyProfiles in legacyProfileDirectories() {
            guard fileManager.fileExists(atPath: legacyProfiles.path) else { continue }
            let sources = try profileFiles(in: legacyProfiles)
            guard !sources.isEmpty else { continue }
            for source in sources {
                let target = destination.appendingPathComponent(source.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) { continue }
                try fileManager.copyItem(at: source, to: target)
            }
            Self.logger.info(
                "Migrated \(sources.count) profile(s) from \(legacyProfiles.path, privacy: .public)"
            )
            return
        }
    }

    private func profileFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["env", "json"].contains($0.pathExtension.lowercased()) }
    }

    private func legacyProfileDirectories() -> [URL] {
        var directories: [URL] = []
        if let cachedRoot = ControllerStatusCache.load()?.controllerRoot {
            directories.append(
                URL(fileURLWithPath: cachedRoot).appendingPathComponent("model-profiles", isDirectory: true)
            )
        }
        directories.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("AI/model-profiles", isDirectory: true)
        )
        directories.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "mac-local-runner/FromNAS/autoresearch/model-profiles",
                    isDirectory: true
                )
        )
        return directories
    }

    private func removeLegacyLaunchAgent() {
        let legacy = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/io.modelswitchboard.controller.plist")
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", legacy.path]
        try? process.run()
        try? fileManager.removeItem(at: legacy)
    }
}
