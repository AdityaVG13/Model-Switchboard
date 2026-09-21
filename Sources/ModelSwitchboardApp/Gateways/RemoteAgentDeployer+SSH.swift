import Foundation
import ModelSwitchboardCore
import OSLog

extension RemoteAgentDeployer {
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
    func runSSH(
        ssh: GatewayConfig.Connection.SSH,
        step: String,
        remoteCommand: String,
        stdin: Data
    ) async throws -> String {
        let (process, stdinPipe, stdoutPipe, stderrPipe) = preparedSSHProcess(
            ssh: ssh,
            remoteCommand: remoteCommand
        )
        let (stdoutBox, stderrBox, stdinErrorBox) = attachSSHOutputBoxes(
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        let exited = makeSSHExitStream(process)
        try launchSSH(process, step: step)

        // Watchdog BEFORE the stdin write: the write itself can block forever
        // on a full pipe when the remote never reads (re-auth banner).
        armAndWriteSSHStdin(process, stdinPipe: stdinPipe, stdin: stdin, errorBox: stdinErrorBox)

        await waitForSSHExit(exited)
        return try await finishSSH(
            process: process,
            step: step,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            stdoutBox: stdoutBox,
            stderrBox: stderrBox,
            stdinError: stdinErrorBox.value
        )
    }
}
