import Foundation
import Testing
@testable import ModelSwitchboardCore

@Test func gatewayConfigRoundTripsThroughJSON() throws {
    let gateway = GatewayConfig.ssh(
        name: "DGX Spark",
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
        GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark"),
        GatewayConfig.direct(name: "Lab box", baseURL: "http://10.0.0.9:8877"),
    ]
    GatewayConfigStore.save(gateways, to: defaults)
    #expect(GatewayConfigStore.load(from: defaults) == gateways)
}

@Test func gatewayConfigStoreQuarantinesCorruptDataWithoutWiping() throws {
    let suiteName = "io.modelswitchboard.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let corrupt = Data("not json".utf8)
    defaults.set(corrupt, forKey: GatewayConfigStore.defaultsKey)
    #expect(GatewayConfigStore.loadResult(from: defaults) == .corrupt)
    #expect(GatewayConfigStore.load(from: defaults).isEmpty)
    #expect(defaults.data(forKey: GatewayConfigStore.corruptBackupKey) == corrupt)

    // Accidental empty save must not clobber the corrupt blob.
    GatewayConfigStore.save([], to: defaults)
    #expect(defaults.data(forKey: GatewayConfigStore.defaultsKey) == corrupt)

    // A real write replaces the blob and clears the quarantine.
    let gateways = [GatewayConfig.ssh(name: "Spark", sshHost: "spark")]
    GatewayConfigStore.save(gateways, to: defaults)
    #expect(GatewayConfigStore.load(from: defaults) == gateways)
    #expect(defaults.data(forKey: GatewayConfigStore.corruptBackupKey) == nil)
}

@Test func gatewayContextForConfigIsRemote() {
    let config = GatewayConfig.ssh(name: "Spark", sshHost: "spark")
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
    #expect(config.ssh?.sshUser == "gpuadmin")
    #expect(config.ssh?.sshHost == "spark.local")
    #expect(config.ssh?.sshPort == 22)
    #expect(config.remotePort == 8877)
}

@Test func linkCodeDefaultsAndDecoding() throws {
    let bare = try #require(GatewayLinkCode.parse("modelswitchboard-gateway://box-01"))
    #expect(bare.name == "box-01")
    #expect(bare.ssh?.sshUser.isEmpty == true)
    #expect(bare.remotePort == 8877)

    let encoded = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://gpu%20admin@10.0.0.9:2222?name=lab%20box&agent_port=9001"
    ))
    #expect(encoded.ssh?.sshUser == "gpu admin")
    #expect(encoded.name == "lab box")
    #expect(encoded.ssh?.sshPort == 2222)
    #expect(encoded.remotePort == 9001)
}

@Test func linkCodeDirectModeBuildsDirectGateway() throws {
    // Emitted by `model-switchboard-agent link --tailscale`.
    let config = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.tail1234.ts.net?name=spark&agent_port=8877&mode=direct"
    ))
    #expect(config.kind == .direct)
    #expect(config.name == "spark")
    #expect(config.direct?.baseURL == "http://spark.tail1234.ts.net:8877")
    #expect(config.ssh == nil)

    let customPort = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://100.101.102.103?agent_port=9001&mode=direct"
    ))
    #expect(customPort.direct?.baseURL == "http://100.101.102.103:9001")
    #expect(customPort.name == "100.101.102.103")
}

@Test func linkCodeRejectsForeignStrings() {
    #expect(GatewayLinkCode.parse("https://example.com") == nil)
    #expect(GatewayLinkCode.parse("modelswitchboard-gateway://") == nil)
    #expect(GatewayLinkCode.parse("not a link at all") == nil)
    #expect(GatewayLinkCode.parse("") == nil)
}

@Test func linkCodeRejectsOptionShapedSSHDestinations() {
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://-oProxyCommand=evil@spark.local?name=spark"
    ) == nil)
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://gpuadmin@-oProxyCommand=evil?name=spark"
    ) == nil)
    #expect(GatewayConfig.ssh(
        name: "x", sshUser: "-oProxyCommand=x", sshHost: "spark"
    ).ssh?.hasUnsafeDestination == true)
    #expect(GatewayConfig.ssh(
        name: "x", sshHost: "-oProxyCommand=x"
    ).ssh?.hasUnsafeDestination == true)
    #expect(GatewayConfig.ssh(
        name: "x", sshUser: "gpuadmin", sshHost: "spark.local"
    ).ssh?.hasUnsafeDestination == false)
}

@Test func endpointSummaryDescribesConnection() {
    let direct = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
    #expect(direct.endpointSummary == "http://10.0.0.9:8877")

    let ssh = GatewayConfig.ssh(name: "Spark", sshUser: "gpuadmin", sshHost: "spark.local")
    #expect(ssh.endpointSummary == "ssh gpuadmin@spark.local → 127.0.0.1:8877")

    let customPort = GatewayConfig.ssh(name: "Spark", sshHost: "spark.local", sshPort: 2222)
    #expect(customPort.ssh?.destination == "spark.local")
    #expect(customPort.endpointSummary == "ssh spark.local -p 2222 → 127.0.0.1:8877")
}

@Test func detectsTailscaleCGNATAddresses() {
    #expect(GatewayConfig.isTailscaleCGNATAddress("100.64.0.1"))
    #expect(GatewayConfig.isTailscaleCGNATAddress("100.101.102.103"))
    #expect(GatewayConfig.isTailscaleCGNATAddress("100.127.255.255"))
    #expect(!GatewayConfig.isTailscaleCGNATAddress("100.63.0.1"))
    #expect(!GatewayConfig.isTailscaleCGNATAddress("10.0.0.9"))
    #expect(!GatewayConfig.isTailscaleCGNATAddress("spark.tail1234.ts.net"))
}

@Test func linkCodeRejectsOutOfRangePorts() {
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.local?agent_port=0"
    ) == nil)
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.local?agent_port=999999"
    ) == nil)
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.local:70000?agent_port=8877"
    ) == nil)
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.local?agent_port=8877"
    ) != nil)
}

@Test func linkCodeParsesExplicitModeTokens() throws {
    // Current agent emits `mode=ssh` on SSH links (single kind token on the wire).
    let ssh = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://gpuadmin@spark.local?name=spark&agent_port=8877&mode=ssh"
    ))
    #expect(ssh.kind == .ssh)
    #expect(ssh.ssh?.sshUser == "gpuadmin")
    #expect(ssh.ssh?.sshHost == "spark.local")

    let direct = try #require(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.tail1234.ts.net?name=spark&agent_port=8877&mode=direct"
    ))
    #expect(direct.kind == .direct)
    #expect(direct.direct?.baseURL == "http://spark.tail1234.ts.net:8877")
}

@Test func linkCodeRefusesUnknownModeInsteadOfGuessingKind() {
    // Unknown kind token: refuse rather than shape-sniff a kind from the URL.
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.local?name=spark&agent_port=8877&mode=port-forward"
    ) == nil)
    #expect(GatewayLinkCode.parse(
        "modelswitchboard-gateway://spark.local?name=spark&agent_port=8877&mode=DIRECT"
    )?.kind == .direct)
}

@Test func directGatewayEncodesOnlyDirectKeys() throws {
    let direct = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
    let data = try JSONEncoder().encode(direct)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["kind"] as? String == "direct")
    #expect(object["baseURL"] as? String == "http://10.0.0.9:8877")
    // The ssh kind's fields cannot exist on a direct gateway — not even as dead keys.
    #expect(object["sshUser"] == nil)
    #expect(object["sshHost"] == nil)
    #expect(object["sshPort"] == nil)
    #expect(object["identityFile"] == nil)
    #expect(object["identityAgent"] == nil)
}

@Test func sshGatewayEncodesOnlySSHKeys() throws {
    let ssh = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark.local")
    let data = try JSONEncoder().encode(ssh)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["kind"] as? String == "ssh")
    #expect(object["sshHost"] as? String == "spark.local")
    #expect(object["baseURL"] == nil)
}

@Test func legacyBlobWithDeadFieldsDecodesAndDropsThemOnSave() throws {
    // Blobs written before the collapse carry every field for every kind
    // (kind switched in the old settings form left dead ssh fields behind on
    // direct gateways). Decode ignores the foreign-kind keys; re-encode
    // shrinks the gateway to its legal shape — the migration path.
    let legacy = """
    [{"id":"g1","name":"Lab","kind":"direct","baseURL":"http://10.0.0.9:8877",\
    "sshUser":"leftover","sshHost":"old-spark","sshPort":2222,"remotePort":8877,\
    "identityFile":"~/.ssh/old","identityAgent":null,"enabled":true}]
    """
    let decoded = try JSONDecoder().decode([GatewayConfig].self, from: Data(legacy.utf8))
    let gateway = try #require(decoded.first)
    #expect(gateway.kind == .direct)
    #expect(gateway.direct?.baseURL == "http://10.0.0.9:8877")
    #expect(gateway.ssh == nil)

    let reencoded = try JSONEncoder().encode(decoded)
    let object = try #require(
        try JSONSerialization.jsonObject(with: reencoded) as? [[String: Any]]
    )
    #expect(object.first?["sshHost"] == nil)
    #expect(object.first?["sshUser"] == nil)
}

@Test func illegalDirectSSHHybridIsUnrepresentable() {
    // The old open product (`GatewayConfig(name:kind:.direct, sshHost: ...)`)
    // no longer compiles: the factories take exactly the fields their kind
    // may carry. SSH fields are unrepresentable on a direct gateway (nil
    // payload, not empty-string projections).
    let direct = GatewayConfig.direct(name: "Lab", baseURL: "http://10.0.0.9:8877")
    #expect(direct.ssh == nil)
    #expect(direct.direct != nil)
    let ssh = GatewayConfig.ssh(name: "Spark", sshHost: "spark.local")
    #expect(ssh.direct == nil)
    #expect(ssh.ssh != nil)
}
