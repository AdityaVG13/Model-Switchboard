import Foundation

extension SSHTunnelManager {
    nonisolated var localBaseURL: String { "http://127.0.0.1:\(localPort)" }

    nonisolated func tunnelArguments() -> [String] {
        SSHInvocation.arguments(
            to: SSHInvocation.Target(
                destination: configuration.destination,
                sshPort: configuration.sshPort,
                identityFile: configuration.identityFile,
                identityAgent: configuration.identityAgent
            ),
            prefix: [
                "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ConnectTimeout=8",
                "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=2",
                "-o", "ControlMaster=auto",
                "-S", controlSocketPath(),
                "-L", "127.0.0.1:\(localPort):127.0.0.1:\(configuration.remotePort)",
            ]
        )
    }

    nonisolated func controlSocketPath() -> String {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.modelswitchboard/ssh", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Unix socket paths are length-limited; keep the name short.
        return directory.appendingPathComponent(controlSocketFileName).path
    }
}
