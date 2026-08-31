import Foundation
import ModelSwitchboardCore
import OSLog

/// Deploys the bundled remote agent to an SSH gateway host, so the remote
/// machine never downloads anything: the app pushes the agent modules and
/// runs the bundled installer over the user's own SSH connection.
actor RemoteAgentDeployer {
    struct Result: Sendable, Equatable {
        let pairingLink: String?
        /// Bearer token printed by the Tailscale installer (empty for unauthenticated installs).
        let authToken: String?
        let log: String
    }

    enum DeployError: Error, Equatable {
        case missingResources
        case sshFailed(step: String, message: String)
    }

    private static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "agent-deployer")
    private static let remoteRoot = ".local/share/model-switchboard-agent"

    private let executableURL: URL
    private let agentSourceURL: URL
    private let coreSourceURL: URL
    private let discoverySourceURL: URL
    private let installerURL: URL
    /// Hard cap per ssh invocation. ssh prompts that BatchMode cannot answer
    /// (Tailscale SSH re-auth, host-key confirm, password) otherwise hang the
    /// push forever and the UI sticks on "Pushing agent…".
    nonisolated let sshDeadline: TimeInterval

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        agentSourceURL: URL? = nil,
        coreSourceURL: URL? = nil,
        discoverySourceURL: URL? = nil,
        installerURL: URL? = nil,
        sshDeadline: TimeInterval = 120
    ) {
        self.executableURL = executableURL
        self.agentSourceURL = agentSourceURL ?? Self.bundledResource("model_switchboard_agent.py")
        self.coreSourceURL = coreSourceURL ?? Self.bundledResource("agent_core.py")
        self.discoverySourceURL = discoverySourceURL ?? Self.bundledResource("discovery.py")
        self.installerURL = installerURL ?? Self.bundledResource("install-remote-agent.sh")
        self.sshDeadline = sshDeadline
    }

    static func bundledResource(_ name: String) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/RemoteAgent")
            .appendingPathComponent(name)
    }

    nonisolated var resourcesAvailable: Bool {
        FileManager.default.isReadableFile(atPath: agentSourceURL.path)
            && FileManager.default.isReadableFile(atPath: coreSourceURL.path)
            && FileManager.default.isReadableFile(atPath: discoverySourceURL.path)
            && FileManager.default.isReadableFile(atPath: installerURL.path)
    }

    /// Pushes the agent modules and runs the installer on the gateway host. With
    /// `useTailscale` the agent is set up bound to the host's tailnet address
    /// and the returned pairing link describes a direct (tunnel-less) gateway.
    func deploy(
        to ssh: GatewayConfig.Connection.SSH,
        useTailscale: Bool = false,
        profilesDirectory: String? = nil
    ) async throws -> Result {
        guard resourcesAvailable else { throw DeployError.missingResources }
        if ssh.hasUnsafeDestination {
            throw DeployError.sshFailed(
                step: "validate",
                message: "SSH user/host cannot start with '-' (would be parsed as an ssh option)."
            )
        }
        let coreData = try Data(contentsOf: coreSourceURL)
        let discoveryData = try Data(contentsOf: discoverySourceURL)
        let agentData = try Data(contentsOf: agentSourceURL)
        let installerData = try Data(contentsOf: installerURL)

        // 1. Push core + discovery + agent into the install root (installer
        //    prefers pre-pushed modules over downloading anything). Core first:
        //    discovery and the agent both import it.
        //    SAFETY (cross-process file mutation): files land at
        //    <file>.new first, then a single remote `mv -f` replaces the live
        //    path atomically. Writing directly onto the live module could let
        //    a concurrent `model-switchboard-agent` invocation exec a
        //    partially-written Python file (SyntaxError mid-boot).
        for (step, file, data) in [
            ("push agent core", "agent_core.py", coreData),
            ("push discovery", "discovery.py", discoveryData),
            ("push agent", "model_switchboard_agent.py", agentData),
        ] {
            _ = try await runSSH(
                ssh: ssh,
                step: step,
                remoteCommand: "mkdir -p ~/\(Self.remoteRoot) && cat > ~/\(Self.remoteRoot)/\(file).new && mv -f ~/\(Self.remoteRoot)/\(file).new ~/\(Self.remoteRoot)/\(file)",
                stdin: data
            )
        }

        // 2. Run the installer from stdin: no files land anywhere except the
        //    agent's own install root.
        var installerFlags = "--port \(ssh.remotePort)" + (useTailscale ? " --tailscale" : "")
        var remotePrefix = ""
        if let profilesDirectory {
            let trimmed = profilesDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Prefer env so arbitrary paths (spaces, quotes) stay out of argv parsing.
                remotePrefix =
                    "MODEL_SWITCHBOARD_PROFILES_DIR=\(Self.shellSingleQuoted(trimmed)) "
                if Self.isSimpleShellPath(trimmed) {
                    installerFlags += " --profiles-dir \(trimmed)"
                }
            }
        }
        let output = try await runSSH(
            ssh: ssh,
            step: "run installer",
            remoteCommand: "\(remotePrefix)bash -s -- \(installerFlags)",
            stdin: installerData
        )

        let pairingLink = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(GatewayLinkCode.scheme)://") }
        let authToken = Self.extractAuthToken(from: output)
        return Result(pairingLink: pairingLink, authToken: authToken, log: output)
    }


    /// Single-quote for remote `sh` so spaces/metacharacters in the path stay literal.
    nonisolated static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Paths safe to append as unquoted installer argv (no shell metacharacters).
    nonisolated static func isSimpleShellPath(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-~"))
        return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Prefer a machine-readable `AUTH_TOKEN=` line; fall back to the human
    /// "Paste this bearer token" block the installer prints for Tailscale.
    nonisolated static func extractAuthToken(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        for line in lines {
            if line.hasPrefix("AUTH_TOKEN="), line.count > "AUTH_TOKEN=".count {
                let value = String(line.dropFirst("AUTH_TOKEN=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        if let hintIndex = lines.firstIndex(where: {
            $0.localizedCaseInsensitiveContains("Paste this bearer token")
        }) {
            for line in lines.dropFirst(hintIndex + 1) {
                if line.isEmpty { continue }
                if line.hasPrefix("[") { break }
                if line.hasPrefix("Token file:") { break }
                if line.hasPrefix("modelswitchboard-gateway://") { continue }
                let candidate = line.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
                if candidate.count >= 16 { return candidate }
            }
        }
        return nil
    }

    /// Runs one ssh invocation without blocking the cooperative pool.
    ///
    /// SAFETY (concurrency contract): ssh can wedge indefinitely - a Tailscale
    /// SSH re-auth banner prints and then the process waits for interactive
    /// input WITHOUT reading stdin, so the pushed payload (agent_core.py is
    /// >64KB, the pipe buffer size) makes a naive blocking write hang forever.
    /// Therefore: the deadline watchdog is armed BEFORE the stdin write, the
    /// write runs on a global queue (never the cooperative pool), stdout/
    /// stderr are drained via readability handlers, and completion is awaited
    /// through a termination-handler continuation.
    private func runSSH(
        ssh: GatewayConfig.Connection.SSH,
        step: String,
        remoteCommand: String,
        stdin: Data
    ) async throws -> String {
        var arguments: [String] = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
        ]
        if ssh.sshPort != 22 {
            arguments += ["-p", String(ssh.sshPort)]
        }
        if let identityFile = ssh.identityFile, !identityFile.isEmpty {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        if let identityAgent = ssh.identityAgent, !identityAgent.isEmpty {
            arguments += ["-o", "IdentityAgent=\(identityAgent)"]
        }
        // `--` terminates options so a crafted destination cannot inject
        // `-oProxyCommand=...` (or similar) ahead of the remote command.
        arguments += ["--", ssh.destination, remoteCommand]

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        final class PipeBox: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            func append(_ chunk: Data) {
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }
            var value: Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }
        let stdoutBox = PipeBox()
        let stderrBox = PipeBox()
        let stdinErrorBox = PipeBox()
        for (pipe, box) in [(stdoutPipe, stdoutBox), (stderrPipe, stderrBox)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                box.append(chunk)
            }
        }

        let exited = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exited.continuation.yield(())
            exited.continuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw DeployError.sshFailed(
                step: step,
                message: "could not run ssh: \(error.localizedDescription)"
            )
        }

        // Watchdog BEFORE the stdin write: the write itself can block forever
        // on a full pipe when the remote never reads (re-auth banner).
        let deadlineProcess = process
        DispatchQueue.global().asyncAfter(deadline: .now() + sshDeadline) {
            if deadlineProcess.isRunning {
                deadlineProcess.terminate()
            }
        }

        // Feed stdin off the cooperative pool; FileHandle writes are blocking.
        DispatchQueue.global().async {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                // EPIPE after the watchdog SIGTERM is expected; the deadline
                // error path reports it. Record anyway for diagnostics.
                stdinErrorBox.append(
                    Data("stdin write failed: \(error.localizedDescription)\n".utf8)
                )
            }
        }

        for await _ in exited.stream { break }
        // The process is gone: any remaining pipe data is already buffered in
        // the kernel, so this read cannot block (write end is closed).
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let stdout = stdoutBox.value + stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrBox.value + stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal, process.terminationStatus == Self.sigtermStatus {
                throw DeployError.sshFailed(
                    step: step,
                    message: "SSH did not finish within \(Int(sshDeadline))s - the host is waiting on an interactive prompt (e.g. Tailscale SSH re-auth or a password). Connect once from Terminal, or set a Deploy host (ssh alias) in Settings."
                )
            }
            var stderrLines = String(decoding: stderr, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            if stderrLines.isEmpty, !stdinErrorBox.value.isEmpty {
                stderrLines = String(decoding: stdinErrorBox.value, as: UTF8.self)
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
            }
            let message = SSHTunnelManager.classifyFailure(stderrLines: stderrLines)
            Self.logger.error("deploy \(step, privacy: .public) failed: \(message, privacy: .public)")
            throw DeployError.sshFailed(step: step, message: message)
        }
        return String(decoding: stdout, as: UTF8.self)
    }

    /// exit status 128+15 as reported for a SIGTERM-terminated child.
    private static let sigtermStatus = 15
}
