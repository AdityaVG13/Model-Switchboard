import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

private struct FakeSSHFixture {
    let directory: URL
    let executable: URL

    /// A stand-in ssh that records each invocation's arguments and stdin, and
    /// answers the installer step with a pairing code like the real one.
    init(exitCode: Int32 = 0, stderr: String = "") throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("msw-deployer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("fake-ssh")
        let script = """
        #!/bin/bash
        dir="\(directory.path)"
        n=$(ls "$dir" | grep -c '^args-' || true)
        printf '%s\\n' "$@" > "$dir/args-$n"
        cat > "$dir/stdin-$n"
        \(stderr.isEmpty ? "" : "echo \"\(stderr)\" >&2")
        if [ "\(exitCode)" != "0" ]; then exit \(exitCode); fi
        if printf '%s' "$*" | grep -q 'bash -s'; then
          echo "[INFO] systemd user service enabled and started (port 8877)."
          echo "  modelswitchboard-gateway://gpuadmin@spark.local?name=spark&agent_port=8877"
        fi
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func recordedArguments(_ index: Int) throws -> String {
        try String(contentsOf: directory.appendingPathComponent("args-\(index)"), encoding: .utf8)
    }

    func recordedStdin(_ index: Int) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("stdin-\(index)"))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func makeSources() throws -> (
    agent: URL, core: URL, discovery: URL, installer: URL, base: URL
) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("msw-deployer-src-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let agent = base.appendingPathComponent("model_switchboard_agent.py")
    let core = base.appendingPathComponent("agent_core.py")
    let discovery = base.appendingPathComponent("discovery.py")
    let installer = base.appendingPathComponent("install-remote-agent.sh")
    try "AGENT-PY-CONTENT".write(to: agent, atomically: true, encoding: .utf8)
    try "CORE-PY-CONTENT".write(to: core, atomically: true, encoding: .utf8)
    try "DISCOVERY-PY-CONTENT".write(to: discovery, atomically: true, encoding: .utf8)
    try "INSTALLER-SH-CONTENT".write(to: installer, atomically: true, encoding: .utf8)
    return (agent, core, discovery, installer, base)
}

@Test func deployPushesAgentThenRunsInstaller() async throws {
    let fixture = try FakeSSHFixture()
    defer { fixture.cleanup() }
    let sources = try makeSources()
    defer { try? FileManager.default.removeItem(at: sources.base) }

    let deployer = RemoteAgentDeployer(
        executableURL: fixture.executable,
        agentSourceURL: sources.agent,
        coreSourceURL: sources.core,
        discoverySourceURL: sources.discovery,
        installerURL: sources.installer
    )
    let config = GatewayConfig.ssh(
        name: "Spark",
        sshUser: "gpuadmin", sshHost: "spark.local", sshPort: 2222, remotePort: 9001,
        identityFile: "~/.ssh/spark_key"
    )

    let result = try await deployer.deploy(to: try #require(config.ssh))

    let coreArguments = try fixture.recordedArguments(0)
    #expect(coreArguments.contains("BatchMode=yes"))
    #expect(coreArguments.contains("-p\n2222"))
    #expect(coreArguments.contains("--\ngpuadmin@spark.local\n"))
    #expect(coreArguments.contains("cat > ~/.local/share/model-switchboard-agent/agent_core.py"))
    #expect(try fixture.recordedStdin(0) == Data("CORE-PY-CONTENT".utf8))

    let discoveryArguments = try fixture.recordedArguments(1)
    #expect(discoveryArguments.contains("cat > ~/.local/share/model-switchboard-agent/discovery.py"))
    #expect(try fixture.recordedStdin(1) == Data("DISCOVERY-PY-CONTENT".utf8))

    let pushArguments = try fixture.recordedArguments(2)
    #expect(pushArguments.contains("cat > ~/.local/share/model-switchboard-agent/model_switchboard_agent.py"))
    #expect(pushArguments.contains("/.ssh/spark_key"))
    #expect(try fixture.recordedStdin(2) == Data("AGENT-PY-CONTENT".utf8))

    let installArguments = try fixture.recordedArguments(3)
    #expect(installArguments.contains("bash -s -- --port 9001"))
    #expect(!installArguments.contains("--tailscale"))
    #expect(try fixture.recordedStdin(3) == Data("INSTALLER-SH-CONTENT".utf8))

    #expect(result.pairingLink == "modelswitchboard-gateway://gpuadmin@spark.local?name=spark&agent_port=8877")
}

@Test func tailscaleDeployPassesInstallerFlag() async throws {
    let fixture = try FakeSSHFixture()
    defer { fixture.cleanup() }
    let sources = try makeSources()
    defer { try? FileManager.default.removeItem(at: sources.base) }

    let deployer = RemoteAgentDeployer(
        executableURL: fixture.executable,
        agentSourceURL: sources.agent,
        coreSourceURL: sources.core,
        discoverySourceURL: sources.discovery,
        installerURL: sources.installer
    )
    let config = GatewayConfig.ssh(name: "Spark", sshUser: "gpuadmin", sshHost: "spark.local")

    _ = try await deployer.deploy(to: try #require(config.ssh), useTailscale: true)

    let installArguments = try fixture.recordedArguments(3)
    #expect(installArguments.contains("bash -s -- --port 8877 --tailscale"))
}

@Test func deployFailureClassifiesStderr() async throws {
    let fixture = try FakeSSHFixture(exitCode: 255, stderr: "gpuadmin@spark: Permission denied (publickey).")
    defer { fixture.cleanup() }
    let sources = try makeSources()
    defer { try? FileManager.default.removeItem(at: sources.base) }

    let deployer = RemoteAgentDeployer(
        executableURL: fixture.executable,
        agentSourceURL: sources.agent,
        coreSourceURL: sources.core,
        discoverySourceURL: sources.discovery,
        installerURL: sources.installer
    )
    let config = GatewayConfig.ssh(name: "Spark", sshUser: "gpuadmin", sshHost: "spark.local")

    do {
        _ = try await deployer.deploy(to: try #require(config.ssh))
        Issue.record("expected deploy to fail")
    } catch let error as RemoteAgentDeployer.DeployError {
        guard case .sshFailed(let step, let message) = error else {
            Issue.record("unexpected error \(error)")
            return
        }
        #expect(step == "push agent core")
        #expect(message.contains("ssh-add"))
    }
}

@Test func deployExtractsTailscaleAuthToken() async throws {
    let fixture = try FakeSSHFixture()
    defer { fixture.cleanup() }
    // Override fake-ssh to emit AUTH_TOKEN= on the installer step.
    let script = """
    #!/bin/bash
    dir="\(fixture.directory.path)"
    n=$(ls "$dir" | grep -c '^args-' || true)
    printf '%s\\n' "$@" > "$dir/args-$n"
    cat > "$dir/stdin-$n"
    if printf '%s' "$*" | grep -q 'bash -s'; then
      echo "modelswitchboard-gateway://spark.tail1234.ts.net?mode=direct&agent_port=8877"
      echo "AUTH_TOKEN=tailscale-token-0123456789"
    fi
    exit 0
    """
    try script.write(to: fixture.executable, atomically: true, encoding: .utf8)

    let sources = try makeSources()
    defer { try? FileManager.default.removeItem(at: sources.base) }
    let deployer = RemoteAgentDeployer(
        executableURL: fixture.executable,
        agentSourceURL: sources.agent,
        coreSourceURL: sources.core,
        discoverySourceURL: sources.discovery,
        installerURL: sources.installer
    )
    let result = try await deployer.deploy(
        to: try #require(GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark").ssh),
        useTailscale: true
    )
    #expect(result.authToken == "tailscale-token-0123456789")
    #expect(result.pairingLink?.contains("mode=direct") == true)
}

@Test func extractAuthTokenParsesMachineReadableAndHumanBlocks() {
    let machine = """
    [INFO] done
    AUTH_TOKEN=abc123456789012345
    Token file: /tmp/token
    """
    #expect(RemoteAgentDeployer.extractAuthToken(from: machine) == "abc123456789012345")

    let human = """
    [INFO] Paste this bearer token into the Mac gateway settings (keychain):

      human-token-0123456789ab

    Token file: /tmp/token
    """
    #expect(RemoteAgentDeployer.extractAuthToken(from: human) == "human-token-0123456789ab")
}

@Test func deployRequiresBundledResources() async throws {
    let deployer = RemoteAgentDeployer(
        executableURL: URL(fileURLWithPath: "/usr/bin/true"),
        agentSourceURL: URL(fileURLWithPath: "/nonexistent/agent.py"),
        coreSourceURL: URL(fileURLWithPath: "/nonexistent/agent_core.py"),
        discoverySourceURL: URL(fileURLWithPath: "/nonexistent/discovery.py"),
        installerURL: URL(fileURLWithPath: "/nonexistent/install.sh")
    )
    #expect(deployer.resourcesAvailable == false)
    await #expect(throws: RemoteAgentDeployer.DeployError.missingResources) {
        _ = try await deployer.deploy(to: try #require(GatewayConfig.ssh(name: "x", sshHost: "h").ssh))
    }
}

@Test func shellSingleQuotedEscapesEmbeddedQuotes() {
    #expect(RemoteAgentDeployer.shellSingleQuoted("plain") == "'plain'")
    #expect(RemoteAgentDeployer.shellSingleQuoted("a'b") == "'a'\\''b'")
    #expect(RemoteAgentDeployer.isSimpleShellPath("/home/user/model-profiles"))
    #expect(!RemoteAgentDeployer.isSimpleShellPath("/tmp/has space"))
}
