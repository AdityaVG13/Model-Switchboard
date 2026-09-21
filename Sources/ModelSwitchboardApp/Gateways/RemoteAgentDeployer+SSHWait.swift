import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    func makeSSHExitStream(_ process: Process) -> AsyncStream<Void> {
        let exited = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exited.continuation.yield(())
            exited.continuation.finish()
        }
        return exited.stream
    }

    func launchSSH(_ process: Process, step: String) throws {
        do {
            try process.run()
        } catch {
            throw DeployError.sshFailed(
                step: step,
                message: "could not run ssh: \(error.localizedDescription)"
            )
        }
    }

    func waitForSSHExit(_ stream: AsyncStream<Void>) async {
        for await _ in stream { break }
    }
}
