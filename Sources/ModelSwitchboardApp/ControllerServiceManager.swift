import Foundation
import ServiceManagement

@MainActor
final class ControllerServiceManager {
    static let shared = ControllerServiceManager()
    static let plistName = "io.modelswitchboard.controller.plist"
    static let controllerPort: UInt16 = 8877

    private let fileManager = FileManager.default
    private var attemptedRegistration = false
    private var detachedControllerProcess: Process?

    /// Human-readable reason the controller may be unavailable after `ensureRegistered()`.
    private(set) var lastDiagnostic: String?

    private init() {}

    @discardableResult
    func ensureRegistered() -> String? {
        guard !attemptedRegistration else { return lastDiagnostic }
        attemptedRegistration = true
        lastDiagnostic = nil

        guard bundledServiceAvailable else {
            lastDiagnostic =
                "This app build is missing the embedded controller. Reinstall with Scripts/install.sh (or the DMG) so ModelSwitchboardController and its LaunchAgent are present."
            NSLog("Model Switchboard: %@", lastDiagnostic!)
            return lastDiagnostic
        }

        do {
            try bootstrapSupportDirectory()
            removeLegacyLaunchAgent()
            let service = SMAppService.agent(plistName: Self.plistName)
            switch service.status {
            case .notRegistered:
                try service.register()
            case .requiresApproval, .enabled, .notFound:
                break
            @unknown default:
                break
            }

            if service.status == .enabled {
                // LaunchAgent owns the process; give it a moment to bind.
                waitForController(timeoutSeconds: 1.5)
            } else if !isControllerReachable() {
                launchDetachedControllerIfNeeded()
                waitForController(timeoutSeconds: 2.0)
            }

            if !isControllerReachable() {
                if service.status == .requiresApproval {
                    lastDiagnostic =
                        "Enable Model Switchboard in System Settings → General → Login Items & Extensions so the local controller can start."
                } else if service.status == .notFound {
                    lastDiagnostic =
                        "Controller LaunchAgent was not found in this app bundle. Reinstall Model Switchboard so the embedded controller can register."
                } else {
                    lastDiagnostic =
                        "Could not start the local controller on port \(Self.controllerPort). Try Quit and reopen, or reinstall."
                }
            }
        } catch {
            lastDiagnostic = "Controller registration failed: \(error.localizedDescription)"
            NSLog("Model Switchboard controller registration failed: %@", error.localizedDescription)
            if !isControllerReachable() {
                launchDetachedControllerIfNeeded()
                waitForController(timeoutSeconds: 2.0)
                if isControllerReachable() {
                    lastDiagnostic = nil
                }
            }
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
        guard !isControllerReachable() else { return }
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
            detachedControllerProcess = process
            NSLog("Model Switchboard: launched detached controller (pid %d)", process.processIdentifier)
        } catch {
            NSLog("Model Switchboard: detached controller launch failed: %@", error.localizedDescription)
        }
    }

    private func waitForController(timeoutSeconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if isControllerReachable() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func isControllerReachable() -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.controllerPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        _ = setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        _ = setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connectResult == 0
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

        for legacyProfiles in legacyProfileDirectories() {
            guard fileManager.fileExists(atPath: legacyProfiles.path) else { continue }
            let sources = try fileManager.contentsOfDirectory(at: legacyProfiles, includingPropertiesForKeys: nil)
                .filter { ["env", "json"].contains($0.pathExtension.lowercased()) }
            guard !sources.isEmpty else { continue }
            for source in sources {
                let target = destination.appendingPathComponent(source.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) { continue }
                try fileManager.copyItem(at: source, to: target)
            }
            NSLog(
                "Model Switchboard: migrated %d profile(s) from %@",
                sources.count,
                legacyProfiles.path
            )
            return
        }
    }

    private func legacyProfileDirectories() -> [URL] {
        var directories: [URL] = []
        if let cachedRoot = cachedControllerRootFromStatusCache() {
            directories.append(
                URL(fileURLWithPath: cachedRoot).appendingPathComponent("model-profiles", isDirectory: true)
            )
        }
        // Canonical local profile mirror under ~/AI.
        directories.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("AI/model-profiles", isDirectory: true)
        )
        // Pre-SMAppService controller root (day-one mac-local-runner layout).
        directories.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "mac-local-runner/FromNAS/autoresearch/model-profiles",
                    isDirectory: true
                )
        )
        return directories
    }

    private func cachedControllerRootFromStatusCache() -> String? {
        let cache = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/io.modelswitchboard/controller-status.json")
        guard let data = try? Data(contentsOf: cache),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let payload = object["payload"] as? [String: Any] ?? object
        return payload["controller_root"] as? String
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
