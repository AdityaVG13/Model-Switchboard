import SwiftUI
import WidgetKit
import ModelSwitchboardCore

struct SwitchboardWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SwitchboardWidgetEntry

    var statuses: [ModelProfileStatus] {
        (entry.payload?.statuses ?? []).boardVisible.sortedForDisplay()
    }

    var summary: DashboardSummary {
        DashboardSummary(payload: entry.payload ?? ControllerStatusPayload(statuses: [], benchmark: nil, integrations: []))
    }

    var displayMode: SwitchboardWidgetDisplayMode {
        entry.configuration.displayMode ?? .summary
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.10, green: 0.21, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 10) {
                header
                if let error = entry.errorDescription, entry.payload == nil {
                    offlineState(error)
                } else {
                    content
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(URL(string: "modelswitchboard://open"))
    }
}
