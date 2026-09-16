import Foundation
import ModelSwitchboardCore

/// Shared OpenSSH argv for BatchMode connections.
///
/// Tunnel and deploy add their own prefix/timeout flags. Neither may omit
/// `--` before the destination, or rewrite BatchMode / identity / port.
enum SSHInvocation {
    struct Target: Equatable, Sendable {
        var destination: String
        var sshPort: Int
        var identityFile: String?
        var identityAgent: String?

        init(
            destination: String,
            sshPort: Int = 22,
            identityFile: String? = nil,
            identityAgent: String? = nil
        ) {
            self.destination = destination
            self.sshPort = sshPort
            self.identityFile = identityFile
            self.identityAgent = identityAgent
        }

        init(_ ssh: GatewayConfig.Connection.SSH) {
            self.init(
                destination: ssh.destination,
                sshPort: ssh.sshPort,
                identityFile: ssh.identityFile,
                identityAgent: ssh.identityAgent
            )
        }
    }

    /// `prefix` + BatchMode + `extraOptions` + port/identity + `-- dest` [+ command].
    static func arguments(
        to target: Target,
        prefix: [String] = [],
        extraOptions: [String] = [],
        remoteCommand: String? = nil
    ) -> [String] {
        var arguments = prefix
        arguments += ["-o", "BatchMode=yes"]
        arguments += extraOptions
        if target.sshPort != 22 {
            arguments += ["-p", String(target.sshPort)]
        }
        if let identityFile = target.identityFile, !identityFile.isEmpty {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        if let identityAgent = target.identityAgent, !identityAgent.isEmpty {
            arguments += ["-o", "IdentityAgent=\(identityAgent)"]
        }
        arguments += ["--", target.destination]
        if let remoteCommand, !remoteCommand.isEmpty {
            arguments.append(remoteCommand)
        }
        return arguments
    }

    /// GUI apps launched via `open` usually have no `SSH_AUTH_SOCK`. Copy the
    /// login-session agent socket onto `Process` so BatchMode can use keys
    /// already loaded in the user's ssh-agent / 1Password / Secretive.
    static func applyEnvironment(to process: Process) {
        var env = process.environment ?? ProcessInfo.processInfo.environment
        if let sock = resolvedSSHAuthSock(env: env) {
            env["SSH_AUTH_SOCK"] = sock
        }
        process.environment = env
    }

    static func resolvedSSHAuthSock(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        launchctlValue: () -> String? = { launchctlGetenv("SSH_AUTH_SOCK") }
    ) -> String? {
        if let sock = env["SSH_AUTH_SOCK"], !sock.isEmpty, fileExists(sock) {
            return sock
        }
        guard let sock = launchctlValue()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sock.isEmpty,
              fileExists(sock)
        else { return nil }
        return sock
    }

    private static func launchctlGetenv(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["getenv", key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
