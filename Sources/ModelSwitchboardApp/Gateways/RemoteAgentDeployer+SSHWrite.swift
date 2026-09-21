import Foundation

extension RemoteAgentDeployer {
    func writeSSHStdin(_ stdinPipe: Pipe, data: Data, errorBox: PipeBox) {
        DispatchQueue.global().async {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                // EPIPE after the watchdog SIGTERM is expected; the deadline
                // error path reports it. Record anyway for diagnostics.
                errorBox.append(
                    Data("stdin write failed: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    func isSSHDeadline(_ process: Process) -> Bool {
        process.terminationReason == .uncaughtSignal && process.terminationStatus == Self.sigtermStatus
    }
}
