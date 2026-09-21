import Foundation

extension RemoteAgentDeployer {
    func attachSSHOutputBoxes(stdoutPipe: Pipe, stderrPipe: Pipe) -> (PipeBox, PipeBox, PipeBox) {
        let stdoutBox = PipeBox()
        let stderrBox = PipeBox()
        let stdinErrorBox = PipeBox()
        attachReadability(stdoutPipe, box: stdoutBox)
        attachReadability(stderrPipe, box: stderrBox)
        return (stdoutBox, stderrBox, stdinErrorBox)
    }

    func armAndWriteSSHStdin(
        _ process: Process,
        stdinPipe: Pipe,
        stdin: Data,
        errorBox: PipeBox
    ) {
        armSSHDeadline(process)
        writeSSHStdin(stdinPipe, data: stdin, errorBox: errorBox)
    }
}
