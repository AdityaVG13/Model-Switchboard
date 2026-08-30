import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

/// DIRECT gateways deploy via an explicit Deploy host when set (ssh-config
/// alias), falling back to the URL host. The URL host hangs forever when the
/// remote sshd is Tailscale SSH (interactive re-auth BatchMode cannot pass).
@Test @MainActor func directDeployTargetPrefersExplicitDeployHost() throws {
    let config = GatewayConfig.direct(name: "Spark", baseURL: "http://dgx-spark.tail1234.ts.net:8877")
    var withHost = config
    if case .direct(var payload) = withHost.connection {
        payload.deployHost = "spark"
        withHost.connection = .direct(payload)
    }
    #expect(GatewayHub.agentDeployTarget(for: config)?.sshHost == "dgx-spark.tail1234.ts.net")
    #expect(GatewayHub.agentDeployTarget(for: withHost)?.sshHost == "spark")
    // user@host form — away-from-home, the tailnet IP destination is what works.
    var withUserHost = config
    if case .direct(var payload) = withUserHost.connection {
        payload.deployHost = "aditya@100.122.96.76"
        withUserHost.connection = .direct(payload)
    }
    let target = try #require(GatewayHub.agentDeployTarget(for: withUserHost))
    #expect(target.sshUser == "aditya")
    #expect(target.sshHost == "100.122.96.76")
    #expect(target.destination == "aditya@100.122.96.76")
}

/// Unresponsive ssh (interactive prompt BatchMode cannot answer) must be
/// killed at the deploy deadline, not hang "Pushing agent…" forever.
@Test func deployDeadlineKillsUnresponsiveSSH() async throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("msw-deployer-deadline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let sleepySSH = base.appendingPathComponent("sleepy-ssh")
    try "#!/bin/bash\nsleep 60\n".write(to: sleepySSH, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sleepySSH.path)

    let sources = try makeSources()
    defer { try? FileManager.default.removeItem(at: sources.base) }
    let deployer = RemoteAgentDeployer(
        executableURL: sleepySSH,
        agentSourceURL: sources.agent,
        coreSourceURL: sources.core,
        discoverySourceURL: sources.discovery,
        installerURL: sources.installer,
        sshDeadline: 1
    )
    let started = Date()
    do {
        _ = try await deployer.deploy(
            to: try #require(GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark").ssh)
        )
        Issue.record("expected deadline failure")
    } catch let error as RemoteAgentDeployer.DeployError {
        guard case .sshFailed(let step, let message) = error else {
            Issue.record("unexpected error \(error)")
            return
        }
        #expect(step == "push agent core")
        #expect(message.contains("did not finish within"))
        #expect(message.localizedCaseInsensitiveContains("prompt"))
    }
    #expect(Date().timeIntervalSince(started) < 20)
}
