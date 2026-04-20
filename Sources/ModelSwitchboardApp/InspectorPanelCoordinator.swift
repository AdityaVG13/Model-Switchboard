import Foundation

struct InspectorPanelCoordinator<Panel: Equatable> {
    private(set) var openPanel: Panel?
    private(set) var deferredClosePanel: Panel?

    mutating func show(_ panel: Panel?) -> Panel? {
        openPanel = panel
        if panel != nil {
            deferredClosePanel = nil
        }
        return openPanel
    }

    mutating func toggle(_ panel: Panel) -> Panel? {
        if deferredClosePanel == panel {
            deferredClosePanel = nil
            openPanel = panel
            return openPanel
        }

        deferredClosePanel = nil
        openPanel = openPanel == panel ? nil : panel
        return openPanel
    }

    mutating func requestDeferredClose(of panel: Panel) {
        guard openPanel == panel else { return }
        deferredClosePanel = panel
    }

    mutating func commitDeferredClose(of panel: Panel) -> Panel? {
        guard deferredClosePanel == panel else { return openPanel }
        deferredClosePanel = nil
        if openPanel == panel {
            openPanel = nil
        }
        return openPanel
    }

    mutating func reset() {
        openPanel = nil
        deferredClosePanel = nil
    }
}
