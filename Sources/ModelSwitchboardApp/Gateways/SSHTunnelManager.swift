import Foundation
import ModelSwitchboardCore
import OSLog

/// Maintains one SSH tunnel to a remote gateway's loopback controller, plus
/// dynamic per-model port forwards over the same connection.
///
/// Runs `ssh -N` with `BatchMode=yes` (key/agent auth only - never passwords),
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

        init(ssh: GatewayConfig.Connection.SSH) {
            destination = ssh.destination
            sshPort = ssh.sshPort
            remotePort = ssh.remotePort
            identityFile = ssh.identityFile
            identityAgent = ssh.identityAgent
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

        /// True when the destination would be parsed as an ssh option.
        var isUnsafeDestination: Bool {
            if GatewayConfig.looksLikeSSHOption(destination) { return true }
            return destination.split(separator: "@").contains {
                GatewayConfig.looksLikeSSHOption(String($0))
            }
        }
    }

    private static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "ssh-tunnel")
    private static let establishTimeoutSeconds: TimeInterval = 20
    private static let establishPollSeconds: TimeInterval = 0.25
    private static let stableUptimeSeconds: TimeInterval = 30
    private static let maximumBackoffSeconds: TimeInterval = 60

    nonisolated let gatewayID: String
    nonisolated let configuration: Configuration
    /// Sticky local agent forward port. May be reassigned if the previous
    /// ephemeral bind is stolen before ssh starts (Address already in use).
    /// SAFETY: only mutated inside actor-isolated methods, and a UInt16 store
    /// is a single aligned store; readers (`localBaseURL`, argument builders)
    /// see either the old or the new port, never a torn value.
    nonisolated(unsafe) private(set) var localPort: UInt16
    /// Per-instance control socket leaf name. Must not be keyed only by gateway
    /// id: teardown is fire-and-forget, and a replacement manager for the same
    /// gateway would otherwise race ControlMaster on the old path.
    nonisolated private let controlSocketFileName: String

    private let executableURL: URL
    private let onStateChange: @Sendable (UUID, State) async -> Void
    private let onLocalPortChange: @Sendable (UUID, UInt16) async -> Void
    private(set) var state: State = .idle
    /// Remote model port → local loopback port. Local ports are unique per
    /// tunnel so two gateways can expose the same remote port (e.g. 8080)
    /// without colliding on this Mac.
    private(set) var activeForwards: [Int: Int] = [:]

    private var desiredActive = false
    private var process: Process?
    private var supervisorTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var stderrTail: [String] = []

    /// Per-instance id (not gateway id) - survives only for this manager object.
    nonisolated let instanceID: UUID

    init(
        gatewayID: String,
        configuration: Configuration,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        onStateChange: @escaping @Sendable (UUID, State) async -> Void = { _, _ in },
        onLocalPortChange: @escaping @Sendable (UUID, UInt16) async -> Void = { _, _ in }
    ) {
        self.gatewayID = gatewayID
        self.configuration = configuration
        self.executableURL = executableURL
        self.onStateChange = onStateChange
        self.onLocalPortChange = onLocalPortChange
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
        if configuration.isUnsafeDestination {
            Task {
                await transition(to: .failed(
                    "SSH user/host cannot start with '-' (would be parsed as an ssh option)."
                ))
            }
            return
        }
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
        activeForwards = [:]
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
        await reallocateLocalPortIfTaken()
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
        activeForwards = [:]
        let failure = Self.classifyFailure(stderrLines: stderrTail)
        if Self.looksLikeLocalPortInUse(stderrLines: stderrTail) {
            await reallocateLocalPortIfTaken(force: true)
        }
        return failure
    }

    /// If our sticky local port was stolen after allocateLoopbackPort closed the
    /// probe socket, pick a new free port and notify the hub so the store URL
    /// stays aligned.
    private func reallocateLocalPortIfTaken(force: Bool = false) async {
        if !force, Self.isLoopbackPortFree(localPort) { return }
        let newPort = Self.allocateLoopbackPort()
        guard newPort != 0, newPort != localPort else { return }
        localPort = newPort
        await onLocalPortChange(instanceID, newPort)
    }

    /// The `-L` listener only opens after authentication succeeds. Require both
    /// a local connect *and* a live ControlMaster - bare TCP can succeed against
    /// a port squatter while ssh is still authenticating.
    private func waitUntilEstablished(process: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.establishTimeoutSeconds)
        while Date() < deadline, process.isRunning, desiredActive {
            // canConnectLoopback blocks up to 250ms in connect(2); hop off the
            // cooperative pool so a pool thread is never pinned per poll.
            let connected = await Self.offPool { Self.canConnectLoopback(port: self.localPort) }
            if connected,
               await runControlCommand(["-O", "check"])
            {
                return true
            }
            try? await Task.sleep(for: .seconds(Self.establishPollSeconds))
        }
        return false
    }

    /// Runs `body` on a global-queue thread. Cooperative-pool escape hatch for
    /// bounded blocking syscalls (see SAFETY on runControlCommand).
    private static func offPool<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: body())
            }
        }
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

    /// Aligns per-model forwards with the given remote ports. Prefers mapping
    /// remote N → local N when free; otherwise allocates an ephemeral local
    /// port. Returns the remote→local map that is actually forwarded now.
    @discardableResult
    func syncForwards(remotePorts: Set<Int>) async -> [Int: Int] {
        guard state.isEstablished else { return activeForwards }
        let stale = Set(activeForwards.keys).subtracting(remotePorts)
        let missing = remotePorts.subtracting(activeForwards.keys)
        for remotePort in stale {
            guard let localPort = activeForwards[remotePort] else { continue }
            _ = await runControlCommand(["-O", "cancel", "-L", Self.forwardSpec(local: localPort, remote: remotePort)])
            activeForwards.removeValue(forKey: remotePort)
        }
        for remotePort in missing {
            guard let localPort = allocateForwardLocalPort(preferring: remotePort) else { continue }
            if await runControlCommand(["-O", "forward", "-L", Self.forwardSpec(local: localPort, remote: remotePort)]) {
                activeForwards[remotePort] = localPort
            }
        }
        return activeForwards
    }

    private func restoreForwardsAfterReconnect() async {
        let wanted = activeForwards
        activeForwards = [:]
        guard state.isEstablished, !wanted.isEmpty else { return }
        for (remotePort, preferredLocal) in wanted {
            let localPort: Int
            if isLocalPortAvailableForForward(preferredLocal) {
                localPort = preferredLocal
            } else if let allocated = allocateForwardLocalPort(preferring: remotePort) {
                localPort = allocated
            } else {
                continue
            }
            if await runControlCommand(["-O", "forward", "-L", Self.forwardSpec(local: localPort, remote: remotePort)]) {
                activeForwards[remotePort] = localPort
            }
        }
    }

    /// Local ports already claimed by this tunnel (agent forward + model forwards).
    private var reservedLocalPorts: Set<Int> {
        Set(activeForwards.values).union([Int(localPort)])
    }

    private func isLocalPortAvailableForForward(_ port: Int) -> Bool {
        guard port > 0, port <= 65535 else { return false }
        guard !reservedLocalPorts.contains(port) else { return false }
        return Self.isLoopbackPortFree(UInt16(port))
    }

    /// Prefer the remote port number locally when free; otherwise ephemeral.
    private func allocateForwardLocalPort(preferring remotePort: Int) -> Int? {
        if isLocalPortAvailableForForward(remotePort) {
            return remotePort
        }
        for _ in 0..<5 {
            let allocated = Self.allocateLoopbackPort()
            guard allocated != 0 else { return nil }
            let asInt = Int(allocated)
            if !reservedLocalPorts.contains(asInt) {
                return asInt
            }
        }
        return nil
    }

    /// One `ssh -O` control invocation, awaited without blocking the
    /// cooperative pool.
    ///
    /// SAFETY (concurrency contract): a ControlMaster socket can be alive but
    /// stalled, making `ssh -O` block on network I/O with no internal timeout.
    /// Synchronous `waitUntilExit()` here would pin a cooperative thread for
    /// that duration, so completion is awaited through a termination handler
    /// and the process is SIGTERM'd at `controlCommandTimeout`.
    private func runControlCommand(_ arguments: [String]) async -> Bool {
        let process = Process()
        process.executableURL = executableURL
        // `--` so a destination that looks like an ssh option cannot be
        // interpreted as one (pairing codes / pasted hosts are untrusted).
        process.arguments = ["-S", controlSocketPath()] + arguments + ["--", configuration.destination]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exited.continuation.yield(())
            exited.continuation.finish()
        }
        do {
            try process.run()
        } catch {
            return false
        }
        let deadlineProcess = process
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.controlCommandTimeout) {
            if deadlineProcess.isRunning {
                deadlineProcess.terminate()
            }
        }
        for await _ in exited.stream { break }
        return process.terminationStatus == 0
    }

    private static let controlCommandTimeout: TimeInterval = 5

    private static func forwardSpec(local: Int, remote: Int) -> String {
        "127.0.0.1:\(local):127.0.0.1:\(remote)"
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

    /// True when nothing is currently bound to `127.0.0.1:port`.
    static func isLoopbackPortFree(_ port: UInt16) -> Bool {
        guard port != 0 else { return false }
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    static func looksLikeLocalPortInUse(stderrLines: [String]) -> Bool {
        let joined = stderrLines.joined(separator: "\n").lowercased()
        return joined.contains("address already in use")
            || joined.contains("bind: address already in use")
            || joined.contains("cannot bind")
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
        if lowered.contains("tailscale ssh requires")
            || lowered.contains("to authenticate, visit https://login.tailscale.com")
        {
            return "Tailscale SSH needs re-auth for this host. Run `tailscale up` (or connect once) in Terminal, or set a Deploy host - an ssh-config alias like `spark` - on the gateway in Settings."
        }
        if lowered.contains("permission denied") {
            return "SSH auth failed. BatchMode needs a passphrase-less key or one loaded in an agent - run ssh-add, or set an identity file/agent for this gateway."
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
