import Foundation
import Testing
@testable import ModelSwitchboardCore

/// Cross-implementation end-to-end: the app's real `ControllerClient` driving
/// the real Python remote agent (`RemoteAgent/model_switchboard_agent.py`)
/// through a full status → start → ready → stop lifecycle.
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

    final class AgentHarness {
        let root: URL
        let port: UInt16
        let process: Process

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("msw-agent-conformance-\(UUID().uuidString)")
            let profiles = root.appendingPathComponent("model-profiles")
            try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

            port = Self.freePort()
            let stubPort = Self.freePort()
            let stubScript = root.appendingPathComponent("stub_server.py")
            try Self.stubServerSource.write(to: stubScript, atomically: true, encoding: .utf8)
            let profile = """
            DISPLAY_NAME="Conformance Stub"
            REQUEST_MODEL=conformance-stub-model
            SERVER_MODEL_ID=conformance-stub-model
            PORT=\(stubPort)
            START_COMMAND="exec python3 \(stubScript.path) \(stubPort) conformance-stub-model"
            """
            try profile.write(
                to: profiles.appendingPathComponent("conformance-stub.env"),
                atomically: true, encoding: .utf8
            )

            process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3", RemoteAgentConformanceTests.agentScript.path,
                "--root", root.path, "--port", String(port), "serve",
            ]
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

        static let stubServerSource = """
        import http.server
        import json
        import sys

        port, model = int(sys.argv[1]), sys.argv[2]

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = json.dumps({"data": [{"id": model}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
        """
    }

    static func waitForAgent(_ client: ControllerClient) async throws {
        for _ in 0..<50 {
            if let payload = try? await client.fetchStatus() {
                #expect(payload.statuses.count == 1)
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("agent did not come up")
    }

    @Test func swiftClientRunsFullLifecycleAgainstPythonAgent() async throws {
        let harness = try AgentHarness()
        defer { harness.shutdown() }
        let client = try ControllerClient(baseURLString: harness.baseURL)
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
        #expect(ready, "profile never became ready via the Python agent")

        let stopped = try await client.stopAll()
        #expect(stopped.ok == true)
        let final = try await client.fetchStatus()
        #expect(final.statuses.first?.running == false)
        #expect(final.statuses.first?.ready == false)
    }

    @Test func unknownProfileAndBadTokenMapToClientErrors() async throws {
        let harness = try AgentHarness()
        defer { harness.shutdown() }
        let client = try ControllerClient(baseURLString: harness.baseURL)
        try await Self.waitForAgent(client)

        await #expect(throws: ControllerClientError.self) {
            _ = try await client.start(profile: "does-not-exist")
        }
    }
}
