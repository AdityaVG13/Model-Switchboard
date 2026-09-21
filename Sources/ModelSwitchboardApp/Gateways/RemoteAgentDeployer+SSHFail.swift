import Foundation
import ModelSwitchboardCore
import OSLog

extension RemoteAgentDeployer {
    func throwIfSSHFailed(
        process: Process,
        step: String,
        stderr: Data,
        stdinError: Data
    ) throws {
        guard process.terminationStatus != 0 else { return }
        if isSSHDeadline(process) {
            throw DeployError.sshFailed(
                step: step,
                message: "SSH did not finish within \(Int(sshDeadline))s - the host is waiting on an interactive prompt (e.g. Tailscale SSH re-auth or a password). Connect once from Terminal, or set a Deploy host (ssh alias) in Settings."
            )
        }
        var stderrLines = decodeSSHLines(stderr)
        if stderrLines.isEmpty, !stdinError.isEmpty {
            stderrLines = decodeSSHLines(stdinError)
        }
        let message = SSHTunnelManager.classifyFailure(stderrLines: stderrLines)
        Self.logger.error("deploy \(step, privacy: .public) failed: \(message, privacy: .public)")
        throw DeployError.sshFailed(step: step, message: message)
    }

    /// exit status 128+15 as reported for a SIGTERM-terminated child.
    static let sigtermStatus = 15
}
