import Foundation
import ModelSwitchboardCore

extension SSHInvocation {
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
        guard let sock = launchctlValue()?.nonEmptyTrimmed,
              fileExists(sock)
        else { return nil }
        return sock
    }
}
