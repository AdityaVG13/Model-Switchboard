import Foundation
import ModelSwitchboardCore

extension ControllerService {
    public func stopAll() throws {
        try withMutationLock {
            if let benchmarkPID = readPID("benchmark") {
                ProcessRunner.terminate(benchmarkPID)
                try? fileManager.removeItem(at: pidFile("benchmark"))
            }
            var failures: [String] = []
            for name in try profiles.load().keys.sorted() {
                do { try stop(name) } catch { failures.append("\(name): \(error)") }
            }
            var environment = ProcessInfo.processInfo.environment
            environment["MODEL_SWITCHBOARD_RUN_DIR"] = configuration.runDirectory.path
            _ = try? ProcessRunner.run(
                "/bin/bash", [configuration.stopAllScript.path], environment: environment,
                currentDirectory: configuration.root, check: false
            )
            if !failures.isEmpty {
                throw ControllerError.operationFailed(
                    "Failed to stop profiles: \(failures.joined(separator: "; "))")
            }
        }
    }
}
