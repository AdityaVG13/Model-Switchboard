import AppKit

extension InspectorPanelController {
    func hide(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let window = panelWindow else {
            completion?()
            return
        }
        visibilityGeneration += 1
        let hideGeneration = visibilityGeneration

        NSAnimationContext.runAnimationGroup { context in
            context.duration = hideAnimationDuration
            window.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                guard hideGeneration == self.visibilityGeneration else { return }
                self.finishHide(window, completion: completion)
            }
        }
    }

    func finishHide(
        _ window: InspectorPanelWindow,
        completion: (@MainActor @Sendable () -> Void)?
    ) {
        parentWindow?.removeChildWindow(window)
        parentWindow = nil
        window.orderOut(nil)
        window.alphaValue = 1
        completion?()
    }
}
