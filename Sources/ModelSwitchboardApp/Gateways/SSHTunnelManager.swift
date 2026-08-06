import Foundation
import ModelSwitchboardCore
import OSLog

/// Maintains one SSH tunnel to a remote gateway's loopback controller, plus
/// dynamic per-model port forwards over the same connection.
///
/// Runs `ssh -N` with `BatchMode=yes` (key/agent auth only — never passwords),
/// `ExitOnForwardFailure=yes`, and a ControlMaster socket so model-endpoint
/// forwards can be added and cancelled with `ssh -O` without reconnecting.
/// Restarts with jittered exponential backoff while the gateway stays enabled.
actor SSHTunnelManager {
    enum State: Equatable, Sendable {
        case idle
        case connecting
        case established
        case failed(String)

        var isEstablished: Bool { self == .established }
    }

    struct Configuration: Equatable, Sendable {
        var destination: String
        var sshPort: Int
        var remotePort: Int
        var identityFile: String?
        var identityAgent: String?

        init(config: GatewayConfig) {
            destination = config.sshDestination
            sshPort = config.sshPort
            remotePort = config.remotePort
            identityFile = config.identityFile
            identityAgent = config.identityAgent
        }

        init(
            destination: String,
            sshPort: Int = 22,
            remotePort: Int = 8877,
            identityFile: String? = nil,
            identityAgent: String? = nil
        ) {
            self.destination = destination
            self.sshPort = sshPort
            self.remotePort = remotePort
            self.identityFile = identityFile
            self.identityAgent = identityAgent
        }
    }

    private static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "ssh-tunnel")
    private static let establishTimeoutSeconds: TimeInterval = 20
    private static let establishPollSeconds: TimeInterval = 0.25
    private static let stableUptimeSeconds: TimeInterval = 30
    private static let maximumBackoffSeconds: TimeInterval = 60

    nonisolated let gatewayID: String
    nonisolated let configuration: Configuration
    /// Stable across restarts so the store's base URL never changes mid-session.
    nonisolated let localPort: UInt16
    /// Per-instance control socket leaf name. Must not be keyed only by gateway
    /// id: teardown is fire-and-forget, and a replacement manager for the same
    /// gateway would otherwise race ControlMaster on the old path.
    nonisolated private let controlSocketFileName: String

    private let executableURL: URL
    private let onStateChange: @Sendable (UUID, State) async -> Void
    private(set) var state: State = .idle
    private(set) var activeForwards: Set<Int> = []

    private var desiredActive = false
    private var process: Process?
    private var supervisorTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var stderrTail: [String] = []

    /// Per-instance id (not gateway id) — survives only for this manager object.
    nonisolated let instanceID: UUID

    init(
        gatewayID: String,
        configuration: Configuration,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        onStateChange: @escaping @Sendable (UUID, State) async -> Void = { _, _ in }
    ) {
        self.gatewayID = gatewayID
        self.configuration = configuration
        self.executableURL = executableURL
        self.onStateChange = onStateChange
        // Stable identity so Hub can ignore stale callbacks after a rebuild
        // replaces this tunnel while the old stop() is still finishing.
        self.instanceID = UUID()
        self.localPort = Self.allocateLoopbackPort()
        let shortID = String(gatewayID.replacingOccurrences(of: "-", with: "").prefix(12))
        let nonce = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        self.controlSocketFileName = "\(shortID)-\(nonce).sock"
    }

    nonisolated var localBaseURL: String { "http://127.0.0.1:\(localPort)" }

    // MARK: - Lifecycle

    func start() {
        guard !desiredActive else { return }
        guard localPort != 0 else {
            Task {
                await transition(to: .failed("Could not allocate a local loopback port for the SSH tunnel."))
            }
            return
        }
        desiredActive = true
        consecutiveFailures = 0
        supervisorTask = Task { await supervise() }
    }

    func stop() async {
        desiredActive = false
        supervisorTask?.cancel()
        supervisorTask = nil
        terminateProcess()
        activeForwards = []
        let socketPath = controlSocketPath()
        try? FileManager.default.removeItem(atPath: socketPath)
        await transition(to: .idle)
    }

    private func supervise() async {
        while desiredActive, !Task.isCancelled {
            await transition(to: .connecting)
            let outcome = await runTunnelOnce()
            guard desiredActive, !Task.isCancelled else { break }
            await transition(to: .failed(outcome))
            consecutiveFailures += 1
            let backoff = Self.backoffDelay(afterFailures: consecutiveFailures)
            try? await Task.sleep(for: .seconds(backoff))
        }
    }

    /// Runs one ssh process to termination. Returns the user-facing failure text.
    private func runTunnelOnce() async -> String {
        stderrTail = []
        let process = Process()
        process.executableURL = executableURL
        process.arguments = tunnelArguments()
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let terminated = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            terminated.continuation.yield()
            terminated.continuation.finish()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { await self.appendStderr(text) }
        }

        do {
            try process.run()
        } catch {
            return "Could not run ssh: \(error.localizedDescription)"
        }
        self.process = process

        let established = await waitUntilEstablished(process: process)
        if established {
            consecutiveFailures = 0
            let establishedAt = Date()
            await transition(to: .established)
            await restoreForwardsAfterReconnect()
            for await _ in terminated.stream { break }
            if Date().timeIntervalSince(establishedAt) < Self.stableUptimeSeconds {
                consecutiveFailures += 1
            }
        } else {
            // Give a failed process a moment to flush stderr, then make sure
            // it is gone (it may still be waiting on auth).
            terminateProcess()
            for await _ in terminated.stream { break }
        }
        self.process = nil
        activeForwards = []
        return Self.classifyFailure(stderrLines: stderrTail)
    }

    /// The `-L` listener only opens after authentication succeeds. Require both
    /// a local connect *and* a live ControlMaster — bare TCP can succeed against
    /// a port squatter while ssh is still authenticating.
    private func waitUntilEstablished(process: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.establishTimeoutSeconds)
        while Date() < deadline, process.isRunning, desiredActive {
            if Self.canConnectLoopback(port: localPort),
               runControlCommand(["-O", "check"])
            {
                return true
            }
            try? await Task.sleep(for: .seconds(Self.establishPollSeconds))
        }
        return false
    }

    private func terminateProcess() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
    }

    private func appendStderr(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            stderrTail.append(String(line))
        }
        if stderrTail.count > 20 {
            stderrTail.removeFirst(stderrTail.count - 20)
        }
    }

    private func transition(to newState: State) async {
        guard state != newState else { return }
        state = newState
        Self.logger.info("tunnel \(self.gatewayID, privacy: .public): \(String(describing: newState), privacy: .public)")
        await onStateChange(instanceID, newState)
    }

    // MARK: - Dynamic model-endpoint forwards

    /// Aligns per-model forwards with the given remote ports (same port number
    /// locally, so displayed endpoint URLs stay predictable). Returns the ports
    /// that are actually forwarded now.
    @discardableResult
    func syncForwards(remotePorts: Set<Int>) async -> Set<Int> {
        guard state.isEstablished else { return activeForwards }
        let stale = activeForwards.subtracting(remotePorts)
        let missing = remotePorts.subtracting(activeForwards)
        for port in stale {
            _ = runControlCommand(["-O", "cancel", "-L", Self.forwardSpec(port: port)])
            activeForwards.remove(port)
        }
        for port in missing {
            if runControlCommand(["-O", "forward", "-L", Self.forwardSpec(port: port)]) {
                activeForwards.insert(port)
            }
        }
        return activeForwards
    }

    private func restoreForwardsAfterReconnect() async {
        let wanted = activeForwards
        activeForwards = []
        if !wanted.isEmpty {
            _ = await syncForwards(remotePorts: wanted)
        }
    }

    private func runControlCommand(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        // `--` so a destination that looks like an ssh option cannot be
        // interpreted as one (pairing codes / pasted hosts are untrusted).
        process.arguments = ["-S", controlSocketPath()] + arguments + ["--", configuration.destination]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func forwardSpec(port: Int) -> String {
        "127.0.0.1:\(port):127.0.0.1:\(port)"
    }

    // MARK: - Arguments

    nonisolated func tunnelArguments() -> [String] {
        var arguments: [String] = [
            "-N",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "ControlMaster=auto",
            "-S", controlSocketPath(),
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(configuration.remotePort)",
        ]
        if configuration.sshPort != 22 {
            arguments += ["-p", String(configuration.sshPort)]
        }
        if let identityFile = configuration.identityFile, !identityFile.isEmpty {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        if let identityAgent = configuration.identityAgent, !identityAgent.isEmpty {
            arguments += ["-o", "IdentityAgent=\(identityAgent)"]
        }
        // End-of-options: destinations from settings / pairing codes must not
        // be parsed as ssh flags (e.g. `-oProxyCommand=...`).
        arguments += ["--", configuration.destination]
        return arguments
    }

    nonisolated private func controlSocketPath() -> String {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.modelswitchboard/ssh", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Unix socket paths are length-limited; keep the name short.
        return directory.appendingPathComponent(controlSocketFileName).path
    }

    // MARK: - Static helpers

    static func allocateLoopbackPort() -> UInt16 {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return 0 }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var bound = address
        let bindResult = withUnsafePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 0 }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard nameResult == 0 else { return 0 }
        return UInt16(bigEndian: assigned.sin_port)
    }

    static func canConnectLoopback(port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func backoffDelay(afterFailures failures: Int, jitter: Double = .random(in: 0.8...1.2)) -> TimeInterval {
        let exponent = min(max(failures, 1), 7) - 1
        let base = min(pow(2.0, Double(exponent)), maximumBackoffSeconds)
        return min(base * jitter, maximumBackoffSeconds)
    }

    /// Maps raw ssh stderr to a short remediation the dashboard can show.
    static func classifyFailure(stderrLines: [String]) -> String {
        let stderr = stderrLines.joined(separator: "\n")
        let lowered = stderr.lowercased()
        if lowered.contains("permission denied") {
            return "SSH auth failed. BatchMode needs a passphrase-less key or one loaded in an agent — run ssh-add, or set an identity file/agent for this gateway."
        }
        if lowered.contains("host key verification failed")
            || lowered.contains("remote host identification has changed") {
            return "SSH host key problem. Connect once from Terminal to verify the host key, then reconnect."
        }
        if lowered.contains("address already in use") {
            return "Local forward port is in use. Remove the conflicting listener or re-add the gateway to pick a new port."
        }
        if lowered.contains("connection refused") {
            return "SSH connection refused. Check the host address and that sshd is running."
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "SSH connection timed out. Check that the host is reachable from this network."
        }
        if lowered.contains("could not resolve hostname") {
            return "Could not resolve the SSH host name."
        }
        if stderr.isEmpty {
            return "SSH tunnel exited. Check the gateway's SSH settings."
        }
        let lastLine = stderrLines.last ?? "unknown error"
        return "SSH tunnel failed: \(lastLine)"
    }
}
