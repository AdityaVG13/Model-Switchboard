import AppKit
import SwiftUI
import Testing
@testable import ModelSwitchboardApp

@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

@MainActor
@Test func closeThenReopenSamePanelRestoresChildWindowImmediately() async throws {
    let controller = InspectorPanelController(showAnimationDuration: 0, hideAnimationDuration: 0)
    let parent = NSWindow(
        contentRect: NSRect(x: 420, y: 180, width: 460, height: 620),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )

    controller.show(
        title: "Benchmarks",
        parent: parent,
        width: 290,
        height: 620,
        gap: 10,
        content: AnyView(Text("First Open"))
    )

    let firstPanel = try #require(parent.childWindows?.first as? InspectorPanelWindow)
    #expect((parent.childWindows ?? []).count == 1)
    #expect(firstPanel.title == "Benchmarks")
    #expect(firstPanel.isVisible)
    #expect(firstPanel.frame.minX == parent.frame.minX - 300)
    #expect(firstPanel.frame.minY == parent.frame.minY)

    await withCheckedContinuation { continuation in
        controller.hide {
            continuation.resume()
        }
    }

    #expect((parent.childWindows ?? []).isEmpty)
    #expect(firstPanel.isVisible == false)

    controller.show(
        title: "Benchmarks Reopened",
        parent: parent,
        width: 290,
        height: 620,
        gap: 10,
        content: AnyView(Text("Second Open"))
    )

    let reopenedPanel = try #require(parent.childWindows?.first as? InspectorPanelWindow)
    #expect((parent.childWindows ?? []).count == 1)
    #expect(reopenedPanel === firstPanel)
    #expect(reopenedPanel.title == "Benchmarks Reopened")
    #expect(reopenedPanel.isVisible)
    #expect(reopenedPanel.frame.minX == parent.frame.minX - 300)
    #expect(reopenedPanel.frame.minY == parent.frame.minY)
}

@MainActor
@Test func reopenBeforeHideCompletionCancelsStaleClose() async throws {
    let controller = InspectorPanelController(showAnimationDuration: 0, hideAnimationDuration: 0)
    let parent = NSWindow(
        contentRect: NSRect(x: 420, y: 180, width: 460, height: 620),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )

    controller.show(
        title: "Benchmarks",
        parent: parent,
        width: 290,
        height: 620,
        gap: 10,
        content: AnyView(Text("First Open"))
    )

    let firstPanel = try #require(parent.childWindows?.first as? InspectorPanelWindow)
    var staleHideCompletionCount = 0

    controller.hide {
        staleHideCompletionCount += 1
    }

    controller.show(
        title: "Settings",
        parent: parent,
        width: 290,
        height: 620,
        gap: 10,
        content: AnyView(Text("Reopened Before Close Completed"))
    )

    await drainMainQueue()
    await drainMainQueue()

    let reopenedPanel = try #require(parent.childWindows?.first as? InspectorPanelWindow)
    #expect((parent.childWindows ?? []).count == 1)
    #expect(reopenedPanel === firstPanel)
    #expect(reopenedPanel.title == "Settings")
    #expect(reopenedPanel.isVisible)
    #expect(staleHideCompletionCount == 0)
}
