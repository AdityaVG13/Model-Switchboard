import Foundation
import Testing
@testable import ModelSwitchboardCore

@Test func gatewayConfigRoundTripsThroughJSON() throws {
    let gateway = GatewayConfig(
        name: "DGX Spark",
        kind: .ssh,
        sshUser: "aditya",
        sshHost: "spark.local",
        sshPort: 2222,
        remotePort: 8877,
        identityFile: "~/.ssh/id_ed25519",
        identityAgent: "~/Library/Group Containers/1password/agent.sock",
        enabled: true
    )

    let data = try JSONEncoder().encode([gateway])
    let decoded = try JSONDecoder().decode([GatewayConfig].self, from: data)
    #expect(decoded == [gateway])
}

@Test func gatewayConfigStorePersistsAndReloads() throws {
    let suiteName = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(GatewayConfigStore.load(from: defaults).isEmpty)

    let gateways = [
        GatewayConfig(name: "Spark", kind: .ssh, sshUser: "a", sshHost: "spark"),
        GatewayConfig(name: "Lab box", kind: .direct, baseURL: "http://10.0.0.9:8877"),
    ]
    GatewayConfigStore.save(gateways, to: defaults)
    #expect(GatewayConfigStore.load(from: defaults) == gateways)
}

@Test func gatewayConfigStoreIgnoresCorruptData() throws {
    let suiteName = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(Data("not json".utf8), forKey: GatewayConfigStore.defaultsKey)
    #expect(GatewayConfigStore.load(from: defaults).isEmpty)
}

@Test func gatewayContextForConfigIsRemote() {
    let config = GatewayConfig(name: "Spark", kind: .ssh, sshHost: "spark")
    let context = GatewayContext(config: config)
    #expect(context.id == config.id)
    #expect(context.name == "Spark")
    #expect(context.isLocal == false)
    #expect(GatewayContext.local.isLocal == true)
}

@Test func endpointSummaryDescribesConnection() {
    let direct = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://10.0.0.9:8877")
    #expect(direct.endpointSummary == "http://10.0.0.9:8877")

    let ssh = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "aditya", sshHost: "spark.local")
    #expect(ssh.endpointSummary == "ssh aditya@spark.local → 127.0.0.1:8877")

    let customPort = GatewayConfig(name: "Spark", kind: .ssh, sshHost: "spark.local", sshPort: 2222)
    #expect(customPort.sshDestination == "spark.local")
    #expect(customPort.endpointSummary == "ssh spark.local -p 2222 → 127.0.0.1:8877")
}
