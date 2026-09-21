import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerServiceManager {
    /// Removes a legacy LaunchAgent, awaiting `launchctl` off the main actor.
    ///
    /// SAFETY: `launchctl bootout` talks to launchd and has no internal
    /// timeout; a wedged launchd would otherwise freeze the app on startup.
    /// The wait is bounded and runs off the main queue.
    func removeLegacyLaunchAgent() async {
        let legacy = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/io.modelswitchboard.controller.plist")
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", legacy.path]
        let exited = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exited.continuation.yield(())
            exited.continuation.finish()
        }
        guard (try? process.run()) != nil else {
            try? fileManager.removeItem(at: legacy)
            return
        }
        let deadlineTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning { process.terminate() }
        }
        for await _ in exited.stream { break }
        deadlineTask.cancel()
        try? fileManager.removeItem(at: legacy)
    }
}
