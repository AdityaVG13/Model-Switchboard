import Foundation

extension SSHTunnelManager {
    /// One `ssh -O` control invocation, awaited without blocking the
    /// cooperative pool.
    ///
    /// SAFETY (concurrency contract): a ControlMaster socket can be alive but
    /// stalled, making `ssh -O` block on network I/O with no internal timeout.
    /// Synchronous `waitUntilExit()` here would pin a cooperative thread for
    /// that duration, so completion is awaited through a termination handler
    /// and the process is SIGTERM'd at `controlCommandTimeout`.
    func runControlCommand(_ arguments: [String]) async -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-S", controlSocketPath()] + arguments + ["--", configuration.destination]
        SSHInvocation.applyEnvironment(to: process)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exited.continuation.yield(())
            exited.continuation.finish()
        }
        do {
            try process.run()
        } catch {
            return false
        }
        let deadlineProcess = process
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.controlCommandTimeout) {
            if deadlineProcess.isRunning {
                deadlineProcess.terminate()
            }
        }
        for await _ in exited.stream { break }
        return process.terminationStatus == 0
    }

    static let controlCommandTimeout: TimeInterval = 5
}
