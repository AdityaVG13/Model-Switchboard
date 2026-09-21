import Foundation

extension RemoteAgentDeployer {
    func configuredSSHProcess(
        arguments: [String]
    ) -> (process: Process, stdin: Pipe, stdout: Pipe, stderr: Pipe) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        SSHInvocation.applyEnvironment(to: process)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        return (process, stdinPipe, stdoutPipe, stderrPipe)
    }

    func armSSHDeadline(_ process: Process) {
        let deadlineProcess = process
        DispatchQueue.global().asyncAfter(deadline: .now() + sshDeadline) {
            if deadlineProcess.isRunning {
                deadlineProcess.terminate()
            }
        }
    }
}
