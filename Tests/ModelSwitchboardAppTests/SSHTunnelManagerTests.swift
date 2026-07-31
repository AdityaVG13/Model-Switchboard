import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

private actor StateRecorder {
    private(set) var states: [SSHTunnelManager.State] = []

    func record(_ state: SSHTunnelManager.State) {
        states.append(state)
    }

    func latest() -> SSHTunnelManager.State? {
        states.last
    }
}

private func writeExecutable(_ content: String, name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("msw-tunnel-tests-\(UUID().uuidString)")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private func waitFor(
    timeoutSeconds: TimeInterval = 15,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return await condition()
}

@Test func backoffDelayGrowsExponentiallyAndCaps() {
    #expect(SSHTunnelManager.backoffDelay(afterFailures: 1, jitter: 1.0) == 1)
    #expect(SSHTunnelManager.backoffDelay(afterFailures: 2, jitter: 1.0) == 2)
    #expect(SSHTunnelManager.backoffDelay(afterFailures: 4, jitter: 1.0) == 8)
    #expect(SSHTunnelManager.backoffDelay(afterFailures: 7, jitter: 1.0) == 60)
    #expect(SSHTunnelManager.backoffDelay(afterFailures: 50, jitter: 1.0) == 60)
    #expect(SSHTunnelManager.backoffDelay(afterFailures: 50, jitter: 1.2) == 60)
}

@Test func stderrClassificationCoversCommonFailures() {
    #expect(SSHTunnelManager.classifyFailure(
        stderrLines: ["aditya@spark: Permission denied (publickey,password)."]
    ).contains("ssh-add"))
    #expect(SSHTunnelManager.classifyFailure(
        stderrLines: ["Host key verification failed."]
    ).contains("Terminal"))
    #expect(SSHTunnelManager.classifyFailure(
        stderrLines: ["bind [127.0.0.1]:9000: Address already in use"]
    ).contains("port is in use"))
    #expect(SSHTunnelManager.classifyFailure(
        stderrLines: ["ssh: connect to host spark port 22: Connection refused"]
    ).contains("refused"))
    #expect(SSHTunnelManager.classifyFailure(
        stderrLines: ["ssh: Could not resolve hostname spark.nowhere"]
    ).contains("resolve"))
    #expect(SSHTunnelManager.classifyFailure(stderrLines: []).contains("exited"))
}

@Test func allocatedPortIsUsableAndInitiallyClosed() throws {
    let port = SSHTunnelManager.allocateLoopbackPort()
    #expect(port > 0)
    #expect(SSHTunnelManager.canConnectLoopback(port: port) == false)
}

@Test func tunnelArgumentsIncludeConfiguredOptions() {
    let manager = SSHTunnelManager(
        gatewayID: "gw-args",
        configuration: .init(
            destination: "aditya@spark.local",
            sshPort: 2222,
            remotePort: 9101,
            identityFile: "~/.ssh/spark_ed25519",
            identityAgent: "/tmp/agent.sock"
        )
    )
    let arguments = manager.tunnelArguments()
    let joined = arguments.joined(separator: " ")

    #expect(arguments.first == "-N")
    #expect(arguments.last == "aditya@spark.local")
    #expect(joined.contains("BatchMode=yes"))
    #expect(joined.contains("ExitOnForwardFailure=yes"))
    #expect(joined.contains("ControlMaster=auto"))
    #expect(joined.contains("-p 2222"))
    #expect(joined.contains("IdentityAgent=/tmp/agent.sock"))
    #expect(joined.contains(":9101"))
    #expect(joined.contains("127.0.0.1:\(manager.localPort):127.0.0.1:9101"))
    #expect(joined.contains("/.ssh/spark_ed25519"))
    #expect(!joined.contains("~"))
}

@Test func failedAuthSurfacesClassifiedError() async throws {
    let fakeSSH = try writeExecutable(
        """
        #!/bin/bash
        echo "aditya@spark: Permission denied (publickey)." >&2
        exit 255
        """,
        name: "fake-ssh-denied"
    )
    defer { try? FileManager.default.removeItem(at: fakeSSH.deletingLastPathComponent()) }

    let recorder = StateRecorder()
    let manager = SSHTunnelManager(
        gatewayID: "gw-denied",
        configuration: .init(destination: "aditya@spark"),
        executableURL: fakeSSH,
        onStateChange: { state in await recorder.record(state) }
    )

    await manager.start()
    let sawFailure = await waitFor {
        if case .failed(let message)? = await recorder.latest() {
            return message.contains("ssh-add")
        }
        return false
    }
    await manager.stop()
    #expect(sawFailure)
}

@Test func tunnelBecomesEstablishedWhenForwardPortListens() async throws {
    // A stand-in for ssh: parse the -L spec and listen on the local port,
    // exactly like a real tunnel after successful auth.
    let fakeSSH = try writeExecutable(
        """
        #!/bin/bash
        SPEC=""
        while [ $# -gt 0 ]; do
          case "$1" in
            -L) SPEC="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        PORT=$(printf '%s' "$SPEC" | cut -d: -f2)
        exec python3 -c "import socket, time
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', $PORT))
        s.listen(4)
        time.sleep(120)"
        """,
        name: "fake-ssh-listen"
    )
    defer { try? FileManager.default.removeItem(at: fakeSSH.deletingLastPathComponent()) }

    let recorder = StateRecorder()
    let manager = SSHTunnelManager(
        gatewayID: "gw-up",
        configuration: .init(destination: "aditya@spark"),
        executableURL: fakeSSH,
        onStateChange: { state in await recorder.record(state) }
    )

    await manager.start()
    let established = await waitFor {
        await recorder.latest() == .established
    }
    #expect(established)
    #expect(SSHTunnelManager.canConnectLoopback(port: manager.localPort))

    await manager.stop()
    let stopped = await waitFor {
        await manager.state == .idle
    }
    #expect(stopped)
}
