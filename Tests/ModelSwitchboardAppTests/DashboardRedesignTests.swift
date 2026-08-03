import AppKit
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

// MARK: - Inspector side placement (always prefer left of dashboard)

@Test func inspectorPanelPrefersLeadingAndFlipsWhenOffScreen() {
    let parent = NSRect(x: 500, y: 100, width: 372, height: 620)
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 950)

    #expect(
        InspectorPanelController.panelOriginX(
            parentFrame: parent, screenVisibleFrame: screen, width: 372, gap: 10, side: .leading
        ) == parent.minX - 10 - 372
    )

    #expect(
        InspectorPanelController.panelOriginX(
            parentFrame: parent, screenVisibleFrame: screen, width: 372, gap: 10, side: .trailing
        ) == parent.maxX + 10
    )

    // Trailing still works as a flip target when leading is off-screen.
    let leftEdgeParent = NSRect(x: 4, y: 100, width: 372, height: 620)
    #expect(
        InspectorPanelController.panelOriginX(
            parentFrame: leftEdgeParent, screenVisibleFrame: screen, width: 372, gap: 10, side: .leading
        ) == leftEdgeParent.maxX + 10
    )
}

// MARK: - Runtime filter classification

@MainActor
@Test func runtimeFilterClassifiesMLXAndLlamaCppFamilies() {
    let llama = ModelFixtures.profileStatus(profile: "a", runtime: "llama.cpp", runtimeLabel: "llama.cpp")
    let mlx = ModelFixtures.profileStatus(profile: "b", runtime: "MLX", runtimeLabel: "MLX")
    let vllmMLX = ModelFixtures.profileStatus(profile: "c", runtime: "vLLM MLX", runtimeLabel: "vLLM MLX")
    let unknown = ModelFixtures.profileStatus(profile: "d", runtime: "custom", runtimeLabel: nil)

    #expect(MenuBarContentView.runtimeKind(llama) == .llamaCpp)
    #expect(MenuBarContentView.runtimeKind(mlx) == .mlx)
    #expect(MenuBarContentView.runtimeKind(vllmMLX) == .mlx)
    #expect(MenuBarContentView.runtimeKind(unknown) == nil)
}

@MainActor
@Test func staleRunningStateIsNotTreatedAsDisplayedRunning() {
    let store = SwitchboardStore(
        controllerBaseURL: "http://127.0.0.1:8877",
        features: .base,
        autoStartRefresh: false
    )
    let now = Date(timeIntervalSince1970: 200)
    let status = ModelFixtures.profileStatus()

    store.statuses = [status]
    store.lastUpdated = now.addingTimeInterval(-901)

    #expect(MenuBarContentView.isDisplayedRunning(status, in: store, relativeTo: now) == false)
}
