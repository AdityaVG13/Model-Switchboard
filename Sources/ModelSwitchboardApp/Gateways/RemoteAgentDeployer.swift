import Foundation
import ModelSwitchboardCore
import OSLog

/// Deploys the bundled remote agent to an SSH gateway host, so the remote
/// machine never downloads anything: the app pushes the agent modules and
/// runs the bundled installer over the user's own SSH connection.
actor RemoteAgentDeployer {
    static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "agent-deployer")
    static let remoteRoot = ".local/share/model-switchboard-agent"

    let executableURL: URL
    let agentSourceURL: URL
    let coreSourceURL: URL
    let discoverySourceURL: URL
    let installerURL: URL
    /// Hard cap per ssh invocation. ssh prompts that BatchMode cannot answer
    /// (Tailscale SSH re-auth, host-key confirm, password) otherwise hang the
    /// push forever and the UI sticks on "Pushing agent…".
    nonisolated let sshDeadline: TimeInterval

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        agentSourceURL: URL? = nil,
        coreSourceURL: URL? = nil,
        discoverySourceURL: URL? = nil,
        installerURL: URL? = nil,
        sshDeadline: TimeInterval = 120
    ) {
        self.executableURL = executableURL
        self.agentSourceURL = agentSourceURL ?? Self.bundledResource("model_switchboard_agent.py")
        self.coreSourceURL = coreSourceURL ?? Self.bundledResource("agent_core.py")
        self.discoverySourceURL = discoverySourceURL ?? Self.bundledResource("discovery.py")
        self.installerURL = installerURL ?? Self.bundledResource("install-remote-agent.sh")
        self.sshDeadline = sshDeadline
    }
}
