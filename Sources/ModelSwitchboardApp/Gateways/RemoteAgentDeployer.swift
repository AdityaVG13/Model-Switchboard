import Foundation
import ModelSwitchboardCore
import OSLog

/// Deploys the bundled remote agent to an SSH gateway host, so the remote
/// machine never downloads anything: the app pushes the single agent file and
/// runs the bundled installer over the user's own SSH connection.
actor RemoteAgentDeployer {
    struct Result: Sendable, Equatable {
        let pairingLink: String?
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
    private let installerURL: URL

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        agentSourceURL: URL? = nil,
        installerURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.agentSourceURL = agentSourceURL ?? Self.bundledResource("model_switchboard_agent.py")
        self.installerURL = installerURL ?? Self.bundledResource("install-remote-agent.sh")
    }

    static func bundledResource(_ name: String) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/RemoteAgent")
            .appendingPathComponent(name)
    }

    nonisolated var resourcesAvailable: Bool {
        FileManager.default.isReadableFile(atPath: agentSourceURL.path)
            && FileManager.default.isReadableFile(atPath: installerURL.path)
    }

    /// Pushes the agent and runs the installer on the gateway host. With
    /// `useTailscale` the agent is set up bound to the host's tailnet address
    /// and the returned pairing link describes a direct (tunnel-less) gateway.
    func deploy(to config: GatewayConfig, useTailscale: Bool = false) async throws -> Result {
        guard resourcesAvailable else { throw DeployError.missingResources }
        let agentData = try Data(contentsOf: agentSourceURL)
        let installerData = try Data(contentsOf: installerURL)

        // 1. Push the agent to the final location (the installer prefers a
        //    pre-pushed agent over downloading anything).
        _ = try await runSSH(
            config: config,
            step: "push agent",
            remoteCommand: "mkdir -p ~/\(Self.remoteRoot) && cat > ~/\(Self.remoteRoot)/model_switchboard_agent.py",
            stdin: agentData
        )

        // 2. Run the installer from stdin: no files land anywhere except the
        //    agent's own install root.
        let installerFlags = "--port \(config.remotePort)" + (useTailscale ? " --tailscale" : "")
        let output = try await runSSH(
            config: config,
            step: "run installer",
            remoteCommand: "bash -s -- \(installerFlags)",
            stdin: installerData
        )

        let pairingLink = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(GatewayLinkCode.scheme)://") }
        return Result(pairingLink: pairingLink, log: output)
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
        try? writeHandle.write(contentsOf: stdin)
        try? writeHandle.close()

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
