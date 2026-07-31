import Foundation
import Testing
@testable import ModelSwitchboardCore

@Test func gatewayConfigRoundTripsThroughJSON() throws {
    let gateway = GatewayConfig(
        name: "DGX Spark",
        kind: .ssh,
        sshUser: "gpuadmin",
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

@Test func linkCodeParsesAgentOutputFormat() throws {
    // Exact shape emitted by `model-switchboard-agent link` (see
    // RemoteAgent/model_switchboard_agent.py build_link_code).
    let config = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://gpuadmin@spark.local?name=spark&agent_port=8877\n"
    ))
    #expect(config.kind == .ssh)
    #expect(config.name == "spark")
    #expect(config.sshUser == "gpuadmin")
    #expect(config.sshHost == "spark.local")
    #expect(config.sshPort == 22)
    #expect(config.remotePort == 8877)
}

@Test func linkCodeDefaultsAndDecoding() throws {
    let bare = try #require(GatewayLinkCode.parse("modelswitchboard-gateway://box-01"))
    #expect(bare.name == "box-01")
    #expect(bare.sshUser.isEmpty)
    #expect(bare.remotePort == 8877)

    let encoded = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://gpu%20admin@10.0.0.9:2222?name=lab%20box&agent_port=9001"
    ))
    #expect(encoded.sshUser == "gpu admin")
    #expect(encoded.name == "lab box")
    #expect(encoded.sshPort == 2222)
    #expect(encoded.remotePort == 9001)
}

@Test func linkCodeDirectModeBuildsDirectGateway() throws {
    // Emitted by `model-switchboard-agent link --tailscale`.
    let config = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.tail1234.ts.net?name=spark&agent_port=8877&mode=direct"
    ))
    #expect(config.kind == .direct)
    #expect(config.name == "spark")
    #expect(config.baseURL == "http://spark.tail1234.ts.net:8877")
    #expect(config.sshHost.isEmpty)

    let customPort = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://100.101.102.103?agent_port=9001&mode=direct"
    ))
    #expect(customPort.baseURL == "http://100.101.102.103:9001")
    #expect(customPort.name == "100.101.102.103")
}

@Test func linkCodeRejectsForeignStrings() {
    #expect(GatewayLinkCode.parse("https://example.com") == nil)
    #expect(GatewayLinkCode.parse("modelswitchboard-gateway://") == nil)
    #expect(GatewayLinkCode.parse("not a link at all") == nil)
    #expect(GatewayLinkCode.parse("") == nil)
}

@Test func endpointSummaryDescribesConnection() {
    let direct = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://10.0.0.9:8877")
    #expect(direct.endpointSummary == "http://10.0.0.9:8877")

    let ssh = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "gpuadmin", sshHost: "spark.local")
    #expect(ssh.endpointSummary == "ssh gpuadmin@spark.local → 127.0.0.1:8877")

    let customPort = GatewayConfig(name: "Spark", kind: .ssh, sshHost: "spark.local", sshPort: 2222)
    #expect(customPort.sshDestination == "spark.local")
    #expect(customPort.endpointSummary == "ssh spark.local -p 2222 → 127.0.0.1:8877")
}
