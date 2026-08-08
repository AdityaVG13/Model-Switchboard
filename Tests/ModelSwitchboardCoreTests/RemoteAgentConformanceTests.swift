import Foundation
import Testing
@testable import ModelSwitchboardCore

/// Cross-implementation end-to-end: the app's real `ControllerClient` driving
/// the real Python remote agent through a full status → start → ready → stop
/// lifecycle. Test scaffolding is native Swift (no Python test code).
///
/// This is the wire-compatibility proof for remote gateways: if the agent
/// drifts from the Swift controller contract, these tests fail.
@Suite(.serialized)
struct RemoteAgentConformanceTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // RemoteAgentConformanceTests.swift
        .deletingLastPathComponent()  // ModelSwitchboardCoreTests
        .deletingLastPathComponent()  // Tests
    static let agentScript = repoRoot.appendingPathComponent("RemoteAgent/model_switchboard_agent.py")
    static let discoveryScript = repoRoot.appendingPathComponent("RemoteAgent/discovery.py")

    final class AgentHarness {
        let root: URL
        let port: UInt16
        let authToken: String?
        let process: Process

        init(authToken: String? = nil, extraProfiles: [(name: String, body: String)] = []) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("msw-agent-conformance-\(UUID().uuidString)")
            let profiles = root.appendingPathComponent("model-profiles")
            try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

            // Agent imports discovery as a sibling module next to --root? It loads
            // discovery from the script directory. Keep agent path absolute.
            port = Self.freePort()
            let stubPort = Self.freePort()
            let stubScript = root.appendingPathComponent("openai-stub.swift")
            try Self.stubServerSource.write(to: stubScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: stubScript.path
            )
            let profile = """
            DISPLAY_NAME="Conformance Stub"
            REQUEST_MODEL=conformance-stub-model
            SERVER_MODEL_ID=conformance-stub-model
            PORT=\(stubPort)
            START_COMMAND="exec /usr/bin/env swift \(stubScript.path) \(stubPort) conformance-stub-model"
            """
            try profile.write(
                to: profiles.appendingPathComponent("conformance-stub.env"),
                atomically: true, encoding: .utf8
            )
            for extra in extraProfiles {
                try extra.body.write(
                    to: profiles.appendingPathComponent("\(extra.name).env"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            self.authToken = authToken
            process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var arguments = [
                "python3", RemoteAgentConformanceTests.agentScript.path,
                "--root", root.path, "--port", String(port),
            ]
            if let authToken, !authToken.isEmpty {
                arguments += ["--auth-token", authToken]
            }
            arguments.append("serve")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        func shutdown() {
            process.terminate()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: root)
        }

        var baseURL: String { "http://127.0.0.1:\(port)" }

        func makeClient(authToken override: String? = nil) throws -> ControllerClient {
            try ControllerClient(
                baseURLString: baseURL,
                authToken: override ?? authToken
            )
        }

        static func freePort() -> UInt16 {
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            defer { close(socketFD) }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            _ = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            var assigned = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &assigned) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(socketFD, $0, &length)
                }
            }
            return UInt16(bigEndian: assigned.sin_port)
        }

        /// Native Swift OpenAI-compatible /v1/models stub — no Python test code.
        static let stubServerSource = #"""
        #!/usr/bin/env swift
        import Foundation
        import Darwin

        guard CommandLine.arguments.count >= 3,
              let port = UInt16(CommandLine.arguments[1]) else {
            fputs("usage: openai-stub.swift <port> <model-id>\n", stderr)
            exit(2)
        }
        let model = CommandLine.arguments[2]
        let body = Data("{\"data\":[{\"id\":\"\(model)\"}]}".utf8)

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { exit(1) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindOK = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0, listen(fd, 8) == 0 else { exit(1) }

        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            var request = [UInt8](repeating: 0, count: 4096)
            _ = read(client, &request, request.count)
            var header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            header.withUTF8 { raw in _ = raw.withMemoryRebound(to: UInt8.self) { write(client, $0.baseAddress, $0.count) } }
            body.withUnsafeBytes { raw in
                if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                    _ = write(client, base, body.count)
                }
            }
            close(client)
        }
        """#
    }

    static func waitForAgent(_ client: ControllerClient, expectedProfiles: Int = 1) async throws {
        for _ in 0..<50 {
            if let payload = try? await client.fetchStatus(),
               payload.statuses.count == expectedProfiles {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("agent did not come up")
    }

    @Test func swiftClientRunsFullLifecycleAgainstPythonAgent() async throws {
        guard FileManager.default.isReadableFile(atPath: Self.agentScript.path),
              FileManager.default.isReadableFile(atPath: Self.discoveryScript.path)
        else {
            Issue.record("RemoteAgent python modules missing from repo checkout")
            return
        }

        let harness = try AgentHarness()
        defer { harness.shutdown() }
        let client = try harness.makeClient()
        try await Self.waitForAgent(client)

        let status = try await client.fetchStatus()
        let stub = try #require(status.statuses.first)
        #expect(stub.profile == "conformance-stub")
        #expect(stub.displayName == "Conformance Stub")
        #expect(stub.requestModel == "conformance-stub-model")
        #expect(stub.running == false)
        #expect(status.integrations.isEmpty)
        #expect(status.benchmark?.running == false)

        let doctor = try await client.fetchDoctorReport()
        #expect(doctor.controller.reachable)

        let metrics = try await client.fetchHostMetrics()
        #expect(!(metrics.host ?? "").isEmpty)
        if let source = metrics.gpuSource {
            #expect(["nvidia-smi", "unavailable"].contains(source))
        }

        let started = try await client.start(profile: "conformance-stub")
        #expect(started.ok == true)

        var ready = false
        for _ in 0..<60 {
            let current = try await client.fetchStatus()
            if let profile = current.statuses.first, profile.ready, profile.running {
                #expect(profile.serverIDs == ["conformance-stub-model"])
                #expect(profile.pid != nil)
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(ready, "profile never became ready via the remote agent")

        let stopped = try await client.stopAll()
        #expect(stopped.ok == true)
        let final = try await client.fetchStatus()
        #expect(final.statuses.first?.running == false)
        #expect(final.statuses.first?.ready == false)
    }

    @Test func unknownProfileBadTokenAndUnsupportedIntegrationMapToClientErrors() async throws {
        let token = "conformance-secret-token"
        let harness = try AgentHarness(authToken: token)
        defer { harness.shutdown() }
        let client = try harness.makeClient()
        try await Self.waitForAgent(client)

        await #expect(throws: ControllerClientError.self) {
            _ = try await client.start(profile: "does-not-exist")
        }

        let unauthenticated = try harness.makeClient(authToken: "wrong-token")
        await #expect(throws: ControllerClientError.self) {
            _ = try await unauthenticated.stopAll()
        }

        await #expect(throws: ControllerClientError.self) {
            _ = try await client.runIntegration(id: "droid", action: "sync")
        }
    }

    @Test func statusPayloadMarksProfilesAndReportsReadyCount() async throws {
        guard FileManager.default.isReadableFile(atPath: Self.agentScript.path),
              FileManager.default.isReadableFile(atPath: Self.discoveryScript.path)
        else {
            Issue.record("RemoteAgent python modules missing from repo checkout")
            return
        }

        let harness = try AgentHarness()
        defer { harness.shutdown() }
        let client = try harness.makeClient()
        try await Self.waitForAgent(client)

        let status = try await client.fetchStatus()
        let stub = try #require(status.statuses.first { $0.profile == "conformance-stub" })
        #expect(stub.source == "profile")
        #expect(status.profileTotalCount == status.statuses.filter { $0.source == "profile" }.count)
        #expect(status.profileReadyCount == status.statuses.filter { $0.source == "profile" && $0.ready }.count)
        let counts = ProfileRuntimeCounts(statuses: status.statuses)
        #expect(counts.total == status.profileTotalCount)
        #expect(counts.ready == status.profileReadyCount)
    }

    @Test func sharedPortProfilesConflictOnSwitch() async throws {
        let stubPort = AgentHarness.freePort()
        // Two profiles claim the same port — switch must 409 before launch.
        let shared = """
        DISPLAY_NAME="Conflict A"
        REQUEST_MODEL=conflict-a
        PORT=\(stubPort)
        START_COMMAND="exec sleep 30"
        HEALTHCHECK_MODE=disabled
        """
        let other = """
        DISPLAY_NAME="Conflict B"
        REQUEST_MODEL=conflict-b
        PORT=\(stubPort)
        START_COMMAND="exec sleep 30"
        HEALTHCHECK_MODE=disabled
        """
        // Harness always writes conformance-stub too; use a dedicated root by
        // writing only conflict profiles via a custom harness setup.
        let harness = try AgentHarness(extraProfiles: [
            (name: "conflict-a", body: shared),
            (name: "conflict-b", body: other),
        ])
        defer { harness.shutdown() }
        let client = try harness.makeClient()
        try await Self.waitForAgent(client, expectedProfiles: 3)

        await #expect(throws: ControllerClientError.self) {
            _ = try await client.activate(profile: "conflict-a")
        }
    }
}
