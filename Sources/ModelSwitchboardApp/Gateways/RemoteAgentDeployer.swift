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
    private let discoverySourceURL: URL
    private let installerURL: URL

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        agentSourceURL: URL? = nil,
        discoverySourceURL: URL? = nil,
        installerURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.agentSourceURL = agentSourceURL ?? Self.bundledResource("model_switchboard_agent.py")
        self.discoverySourceURL = discoverySourceURL ?? Self.bundledResource("discovery.py")
        self.installerURL = installerURL ?? Self.bundledResource("install-remote-agent.sh")
    }

    static func bundledResource(_ name: String) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/RemoteAgent")
            .appendingPathComponent(name)
    }

    nonisolated var resourcesAvailable: Bool {
        FileManager.default.isReadableFile(atPath: agentSourceURL.path)
            && FileManager.default.isReadableFile(atPath: discoverySourceURL.path)
            && FileManager.default.isReadableFile(atPath: installerURL.path)
    }

    /// Pushes the agent modules and runs the installer on the gateway host. With
    /// `useTailscale` the agent is set up bound to the host's tailnet address
    /// and the returned pairing link describes a direct (tunnel-less) gateway.
    func deploy(
        to config: GatewayConfig,
        useTailscale: Bool = false,
        profilesDirectory: String? = nil
    ) async throws -> Result {
        guard resourcesAvailable else { throw DeployError.missingResources }
        if config.hasUnsafeSSHDestination {
            throw DeployError.sshFailed(
                step: "validate",
                message: "SSH user/host cannot start with '-' (would be parsed as an ssh option)."
            )
        }
        let agentData = try Data(contentsOf: agentSourceURL)
        let discoveryData = try Data(contentsOf: discoverySourceURL)
        let installerData = try Data(contentsOf: installerURL)

        // 1. Push discovery + agent into the install root (installer prefers
        //    pre-pushed modules over downloading anything).
        _ = try await runSSH(
            config: config,
            step: "push discovery",
            remoteCommand: "mkdir -p ~/\(Self.remoteRoot) && cat > ~/\(Self.remoteRoot)/discovery.py",
            stdin: discoveryData
        )
        _ = try await runSSH(
            config: config,
            step: "push agent",
            remoteCommand: "mkdir -p ~/\(Self.remoteRoot) && cat > ~/\(Self.remoteRoot)/model_switchboard_agent.py",
            stdin: agentData
        )

        // 2. Run the installer from stdin: no files land anywhere except the
        //    agent's own install root.
        var installerFlags = "--port \(config.remotePort)" + (useTailscale ? " --tailscale" : "")
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
            config: config,
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

    private func runSSH(
        config: GatewayConfig,
        step: String,
        remoteCommand: String,
        stdin: Data
    ) async throws -> String {
        var arguments: [String] = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
        ]
        if config.sshPort != 22 {
            arguments += ["-p", String(config.sshPort)]
        }
        if let identityFile = config.identityFile, !identityFile.isEmpty {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        if let identityAgent = config.identityAgent, !identityAgent.isEmpty {
            arguments += ["-o", "IdentityAgent=\(identityAgent)"]
        }
        // `--` terminates options so a crafted destination cannot inject
        // `-oProxyCommand=...` (or similar) ahead of the remote command.
        arguments += ["--", config.sshDestination, remoteCommand]

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // Feed stdin off the current task; FileHandle writes are blocking.
        let writeHandle = stdinPipe.fileHandleForWriting
        do {
            try writeHandle.write(contentsOf: stdin)
            try writeHandle.close()
        } catch {
            process.terminate()
            throw DeployError.sshFailed(
                step: step,
                message: "failed to write install payload over SSH: \(error.localizedDescription)"
            )
        }

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrLines = String(decoding: stderr, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let message = SSHTunnelManager.classifyFailure(stderrLines: stderrLines)
            Self.logger.error("deploy \(step, privacy: .public) failed: \(message, privacy: .public)")
            throw DeployError.sshFailed(step: step, message: message)
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}
