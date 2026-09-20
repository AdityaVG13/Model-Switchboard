import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

/// DIRECT gateways deploy via an explicit Deploy host when set (ssh-config
/// alias), falling back to the URL host. The URL host hangs forever when the
/// remote sshd is Tailscale SSH (interactive re-auth BatchMode cannot pass).
@Test @MainActor func directDeployTargetPrefersExplicitDeployHost() throws {
    let config = GatewayConfig.direct(name: "Lab", baseURL: "http://host.example.ts.net:8877")
    var withHost = config
    if case .direct(var payload) = withHost.connection {
        payload.deployHost = "gpu"
        withHost.connection = .direct(payload)
    }
    #expect(GatewayHub.agentDeployTarget(for: config)?.sshHost == "host.example.ts.net")
    #expect(GatewayHub.agentDeployTarget(for: withHost)?.sshHost == "gpu")
    // user@host form - away-from-home, the tailnet IP destination is what works.
    var withUserHost = config
    if case .direct(var payload) = withUserHost.connection {
        payload.deployHost = "user@100.64.1.2"
        withUserHost.connection = .direct(payload)
    }
    let target = try #require(GatewayHub.agentDeployTarget(for: withUserHost))
    #expect(target.sshUser == "user")
    #expect(target.sshHost == "100.64.1.2")
    #expect(target.destination == "user@100.64.1.2")
}

@Test @MainActor func recoveredLegacyIPv4DeployHostWinsOverMagicDNSURL() throws {
    let legacy = """
    {"id":"g1","name":"Lab","kind":"direct",\
    "baseURL":"http://gpu.example.ts.net:8877",\
    "sshUser":"gpuadmin","sshHost":"100.64.1.2","sshPort":22,"remotePort":8877,\
    "enabled":true}
    """
    let config = try JSONDecoder().decode(GatewayConfig.self, from: Data(legacy.utf8))
    let target = try #require(GatewayHub.agentDeployTarget(for: config))
    #expect(target.sshUser == "gpuadmin")
    #expect(target.sshHost == "100.64.1.2")
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
