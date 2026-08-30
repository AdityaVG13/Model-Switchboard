import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

@MainActor
@Test func gatewayConnectionBadgeDirectShowsErrorWhenStoreFailed() {
    let config = GatewayConfig.direct(name: "Lab", baseURL: "http://lab.example:8741")
    let store = SwitchboardStore(
        controllerBaseURL: config.direct?.baseURL ?? ControllerEndpointDefaults.baseURLString,
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    store.refreshState = .failed(message: "agent unreachable")
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "DIRECT · ERROR")
    #expect(GatewayConnectionBadge.updateActionTitle(for: runtime) == "Update")
}

@MainActor
@Test func gatewayConnectionBadgeSSHTunneledVsFailed() {
    let config = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark")
    let store = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)

    runtime.tunnelState = .established
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "SSH · TUNNELED")

    runtime.tunnelState = .failed("connection refused")
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "SSH · FAILED")

    runtime.tunnelState = .established
    store.refreshState = .failed(message: "status timeout")
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "SSH · ERROR")
}

@MainActor
@Test func gatewayConnectionBadgeUpdateActionIsSeparateFromStatus() {
    let config = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark")
    let store = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)
    runtime.tunnelState = .established
    runtime.forceUpdatePhase = .updating("Pushing agent…")
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "SSH · TUNNELED")
    #expect(GatewayConnectionBadge.updateActionTitle(for: runtime) == "Updating…")
    #expect(GatewayConnectionBadge.help(for: runtime) == "Pushing agent…")

    runtime.forceUpdatePhase = .failed("boom")
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "SSH · TUNNELED")
    #expect(GatewayConnectionBadge.updateActionTitle(for: runtime) == "Retry")
    #expect(GatewayConnectionBadge.help(for: runtime) == "boom")
}

@MainActor
@Test func gatewayConnectionBadgeStaleUsesUpdateAgentTitle() {
    let config = GatewayConfig.ssh(name: "Spark", sshUser: "a", sshHost: "spark")
    let store = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)
    runtime.tunnelState = .established
    #expect(GatewayConnectionBadge.statusText(for: runtime) == "SSH · TUNNELED")
    #expect(GatewayConnectionBadge.updateActionTitle(for: runtime, agentStale: true) == "Update agent")
    let help = GatewayConnectionBadge.help(
        for: runtime,
        agentStale: true,
        remoteVersion: "1.1.2"
    )
    #expect(help.contains("1.1.2"))
    #expect(help.contains(RemoteAgentVersion.bundled))
    #expect(help.localizedCaseInsensitiveContains("update"))
}
