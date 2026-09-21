import SwiftUI

struct MenuBarPanelChrome: ViewModifier {
    let inspectorAnimation: Animation
    let inspectorOpenPanel: MenuBarContentView.InspectorPanel?
    let pendingProfileActions: [String: SwitchboardStore.ProfileAction]
    let pendingGlobalActions: Set<SwitchboardStore.GlobalAction>
    let statusCount: Int
    let resolvedColorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .animation(inspectorAnimation, value: inspectorOpenPanel)
            // Scope snappy animations to pending action chrome only - do not animate
            // full status list replacements (causes black flicker in MenuBarExtra).
            .animation(.snappy(duration: 0.18), value: pendingProfileActions)
            .animation(.snappy(duration: 0.18), value: pendingGlobalActions)
            .transaction(value: statusCount) { transaction in
                // Status payload apply should be instant; never crossfade the panel.
                if transaction.animation != nil {
                    transaction.animation = nil
                }
            }
            .preferredColorScheme(resolvedColorScheme)
    }
}
