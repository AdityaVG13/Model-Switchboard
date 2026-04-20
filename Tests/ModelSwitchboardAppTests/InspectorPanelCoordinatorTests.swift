import Testing
@testable import ModelSwitchboardApp

private enum TestPanel: String {
    case benchmarks
    case settings
}

@Test func deferredCloseCanBeCancelledByImmediateReopen() {
    var coordinator = InspectorPanelCoordinator<TestPanel>()

    #expect(coordinator.show(.benchmarks) == .benchmarks)
    coordinator.requestDeferredClose(of: .benchmarks)

    let reopenedPanel = coordinator.toggle(.benchmarks)
    let committedPanel = coordinator.commitDeferredClose(of: .benchmarks)

    #expect(reopenedPanel == .benchmarks)
    #expect(committedPanel == .benchmarks)
    #expect(coordinator.openPanel == .benchmarks)
    #expect(coordinator.deferredClosePanel == nil)
}

@Test func deferredCloseHidesPanelWhenNotCancelled() {
    var coordinator = InspectorPanelCoordinator<TestPanel>()

    #expect(coordinator.show(.benchmarks) == .benchmarks)
    coordinator.requestDeferredClose(of: .benchmarks)

    let committedPanel = coordinator.commitDeferredClose(of: .benchmarks)

    #expect(committedPanel == nil)
    #expect(coordinator.openPanel == nil)
    #expect(coordinator.deferredClosePanel == nil)
}

@Test func switchingPanelsClearsDeferredCloseForPreviousPanel() {
    var coordinator = InspectorPanelCoordinator<TestPanel>()

    #expect(coordinator.show(.benchmarks) == .benchmarks)
    coordinator.requestDeferredClose(of: .benchmarks)

    let nextPanel = coordinator.toggle(.settings)
    let committedPanel = coordinator.commitDeferredClose(of: .benchmarks)

    #expect(nextPanel == .settings)
    #expect(committedPanel == .settings)
    #expect(coordinator.openPanel == .settings)
    #expect(coordinator.deferredClosePanel == nil)
}

@Test func explicitShowClearsDeferredCloseForSamePanel() {
    var coordinator = InspectorPanelCoordinator<TestPanel>()

    #expect(coordinator.show(.benchmarks) == .benchmarks)
    coordinator.requestDeferredClose(of: .benchmarks)

    let shownPanel = coordinator.show(.benchmarks)
    let committedPanel = coordinator.commitDeferredClose(of: .benchmarks)

    #expect(shownPanel == .benchmarks)
    #expect(committedPanel == .benchmarks)
    #expect(coordinator.openPanel == .benchmarks)
    #expect(coordinator.deferredClosePanel == nil)
}
