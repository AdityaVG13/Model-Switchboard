import Foundation
import ModelSwitchboardCore
import OSLog

extension RemoteAgentDeployer {
    func finishSSH(
        process: Process,
        step: String,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        stdoutBox: PipeBox,
        stderrBox: PipeBox,
        stdinError: Data
    ) async throws -> String {
        // The process is gone: any remaining pipe data is already buffered in
        // the kernel, so this read cannot block (write end is closed).
        let stdout = collectPipe(stdoutPipe, box: stdoutBox)
        let stderr = collectPipe(stderrPipe, box: stderrBox)
        try throwIfSSHFailed(
            process: process,
            step: step,
            stderr: stderr,
            stdinError: stdinError
        )
        return String(decoding: stdout, as: UTF8.self)
    }
}
