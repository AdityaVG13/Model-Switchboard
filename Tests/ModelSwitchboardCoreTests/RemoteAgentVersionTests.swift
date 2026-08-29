import Foundation
import Testing
@testable import ModelSwitchboardCore

@Test func bundledRemoteAgentVersionMatchesPythonSource() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repoRoot.appendingPathComponent("RemoteAgent/model_switchboard_agent.py"),
        encoding: .utf8
    )
    #expect(source.contains("AGENT_VERSION = \"\(RemoteAgentVersion.bundled)\""))
}

@Test func remoteAgentVersionCompareIsNumericDotted() {
    #expect(RemoteAgentVersion.compare("1.1.2", "1.1.3") == .orderedAscending)
    #expect(RemoteAgentVersion.compare("1.1.3", "1.1.3") == .orderedSame)
    #expect(RemoteAgentVersion.compare("1.2", "1.1.9") == .orderedDescending)
    #expect(RemoteAgentVersion.compare("1.1", "1.1.0") == .orderedSame)
}

@Test func remoteAgentStaleWhenOlderMissingOrUnsupported() {
    #expect(RemoteAgentVersion.isOlderThanBundled("1.1.2"))
    #expect(!RemoteAgentVersion.isOlderThanBundled(RemoteAgentVersion.bundled))
    #expect(!RemoteAgentVersion.isOlderThanBundled("9.0.0"))
    #expect(RemoteAgentVersion.isOlderThanBundled(nil))
    #expect(RemoteAgentVersion.isOlderThanBundled("  "))

    let current = HostMetricsPayload(agentVersion: RemoteAgentVersion.bundled)
    #expect(!RemoteAgentVersion.isRemoteStale(metrics: current, unsupported: false))
    #expect(RemoteAgentVersion.isRemoteStale(metrics: current, unsupported: true))
    #expect(!RemoteAgentVersion.isRemoteStale(metrics: nil, unsupported: false))

    let old = HostMetricsPayload(agentVersion: "1.1.2")
    #expect(RemoteAgentVersion.isRemoteStale(metrics: old, unsupported: false))

    let unversioned = HostMetricsPayload(host: "spark")
    #expect(RemoteAgentVersion.isRemoteStale(metrics: unversioned, unsupported: false))
}
