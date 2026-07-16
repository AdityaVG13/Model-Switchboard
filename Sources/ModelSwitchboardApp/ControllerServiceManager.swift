import Foundation
import ModelSwitchboardCore
import OSLog
import ServiceManagement

private let controllerLaunchAgentPlistName = "io.modelswitchboard.controller.plist"

/// Bundle layout used by ``ControllerServiceManager`` so tests can inject an incomplete app.
struct ControllerBundleLayout {
    var resourceURL: URL?
    var bundleURL: URL
    var fileManager: FileManager

    init(
        resourceURL: URL?,
        bundleURL: URL,
        fileManager: FileManager = .default
    ) {
        self.resourceURL = resourceURL
        self.bundleURL = bundleURL
        self.fileManager = fileManager
    }

    static var main: ControllerBundleLayout {
        ControllerBundleLayout(
            resourceURL: Bundle.main.resourceURL,
            bundleURL: Bundle.main.bundleURL
        )
    }

    var hasEmbeddedController: Bool {
        guard let resourceURL else { return false }
        let binary = resourceURL.appendingPathComponent("ModelSwitchboardController")
        let plist = bundleURL.appendingPathComponent(
            "Contents/Library/LaunchAgents/\(controllerLaunchAgentPlistName)"
        )
        return fileManager.isExecutableFile(atPath: binary.path)
            && fileManager.fileExists(atPath: plist.path)
    }

    var controllerBinaryURL: URL? {
        guard let resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("ModelSwitchboardController")
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }

    var controllerSupportURL: URL? {
        guard let resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("ControllerSupport", isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor
final class ControllerServiceManager {
    static let shared = ControllerServiceManager()
    static let plistName = controllerLaunchAgentPlistName

    private static let logger = Logger(
        subsystem: "io.modelswitchboard.app",
        category: "controller-service"
    )

    private let bundle: ControllerBundleLayout
    private let fileManager: FileManager
    private var attemptedRegistration = false

    /// Set when registration cannot start a controller the panel can talk to.
    private(set) var lastDiagnostic: String?

    init(bundle: ControllerBundleLayout = .main) {
        self.bundle = bundle
        self.fileManager = bundle.fileManager
    }

    /// Registers the LaunchAgent and recovers a reachable loopback controller when needed.
    /// Suspends briefly while probing the port so diagnostics are accurate without blocking `App.init`.
    @discardableResult
    func ensureRegistered() async -> String? {
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
            switch service.status {
            case .notRegistered:
                try service.register()
            case .requiresApproval, .enabled, .notFound:
                break
            @unknown default:
                break
            }

            if service.status == .enabled {
                await waitForController(timeoutSeconds: 1.5)
            } else if !isControllerReachable() {
                launchDetachedControllerIfNeeded()
                await waitForController(timeoutSeconds: 2.0)
            }

            if !isControllerReachable() {
                lastDiagnostic = unreachableDiagnostic(for: service.status)
            }
        } catch {
            let message = "Controller registration failed: \(error.localizedDescription)"
            Self.logger.error("\(message, privacy: .public)")
            lastDiagnostic = message
            if !isControllerReachable() {
                launchDetachedControllerIfNeeded()
                await waitForController(timeoutSeconds: 2.0)
                if isControllerReachable() {
                    lastDiagnostic = nil
                }
            }
        }
        return lastDiagnostic
    }

    var bundledServiceAvailable: Bool {
        bundle.hasEmbeddedController
    }

    private func unreachableDiagnostic(for status: SMAppService.Status) -> String {
        switch status {
        case .requiresApproval:
            return "Enable Model Switchboard in System Settings → General → Login Items & Extensions so the local controller can start."
        case .notFound:
            return "Controller LaunchAgent was not found in this app bundle. Reinstall Model Switchboard so the embedded controller can register."
        case .enabled, .notRegistered:
            return "Could not start the local controller on port \(ControllerEndpointDefaults.port). Try Quit and reopen, or reinstall."
        @unknown default:
            return "Could not start the local controller on port \(ControllerEndpointDefaults.port). Try Quit and reopen, or reinstall."
        }
    }

    private func launchDetachedControllerIfNeeded() {
        guard !isControllerReachable() else { return }
        guard let binary = bundle.controllerBinaryURL else { return }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        do {
            try process.run()
            // Intentionally not retained: orphaned only if already reachable (guarded above).
            // LaunchAgent KeepAlive or a later relaunch owns long-lived serve.
            Self.logger.info("Launched detached controller (pid \(process.processIdentifier))")
        } catch {
            Self.logger.error(
                "Detached controller launch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func waitForController(timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if isControllerReachable() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func isControllerReachable() -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = ControllerEndpointDefaults.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(ControllerEndpointDefaults.host))

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
        guard let source = bundle.controllerSupportURL else { return }
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

    /// Only the last known controller root from status cache -- no machine-specific home layouts.
    private func legacyProfileDirectories() -> [URL] {
        guard let cachedRoot = ControllerStatusCache.load()?.controllerRoot else { return [] }
        return [
            URL(fileURLWithPath: cachedRoot).appendingPathComponent("model-profiles", isDirectory: true)
        ]
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
