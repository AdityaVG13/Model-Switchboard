import AppKit

enum InspectorPanelSide {
    case leading
    case trailing
}

@MainActor
final class InspectorPanelWindow: NSPanel {
    /// Settings needs typing; display panels stay non-activating so click-out
    /// of the menu bar dashboard can dismiss without focus thrash.
    var allowsKeyFocus = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}
