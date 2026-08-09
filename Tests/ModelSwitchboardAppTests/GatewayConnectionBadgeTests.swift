import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

@MainActor
@Test func gatewayConnectionBadgeDirectShowsErrorWhenStoreFailed() {
    let config = GatewayConfig(name: "Lab", kind: .direct, baseURL: "http://lab.example:8741")
    let store = SwitchboardStore(
        controllerBaseURL: config.baseURL.isEmpty
            ? ControllerEndpointDefaults.baseURLString
            : config.baseURL,
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    store.lastError = "agent unreachable"
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)
    #expect(GatewayConnectionBadge.text(for: runtime) == "DIRECT · ERROR")
}

@MainActor
@Test func gatewayConnectionBadgeSSHTunneledVsFailed() {
    let config = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "a", sshHost: "spark")
    let store = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)

    runtime.tunnelState = .established
    #expect(GatewayConnectionBadge.text(for: runtime) == "SSH · TUNNELED")

    runtime.tunnelState = .failed("connection refused")
    #expect(GatewayConnectionBadge.text(for: runtime) == "SSH · FAILED")

    runtime.tunnelState = .established
    store.lastError = "status timeout"
    #expect(GatewayConnectionBadge.text(for: runtime) == "SSH · ERROR")
}

@MainActor
@Test func gatewayConnectionBadgeShowsUpdatingPhase() {
    let config = GatewayConfig(name: "Spark", kind: .ssh, sshUser: "a", sshHost: "spark")
    let store = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:9999",
        features: .base,
        gateway: GatewayContext(config: config),
        autoStartRefresh: false
    )
    let runtime = GatewayRuntime(config: config, store: store, tunnel: nil)
    runtime.tunnelState = .established
    runtime.forceUpdatePhase = .updating("Pushing agent…")
    #expect(GatewayConnectionBadge.text(for: runtime) == "UPDATING…")
    #expect(GatewayConnectionBadge.help(for: runtime) == "Pushing agent…")

    runtime.forceUpdatePhase = .failed("boom")
    #expect(GatewayConnectionBadge.text(for: runtime) == "UPDATE FAILED")
    #expect(GatewayConnectionBadge.help(for: runtime) == "boom")
}
