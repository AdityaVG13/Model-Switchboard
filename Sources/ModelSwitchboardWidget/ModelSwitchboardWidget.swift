import SwiftUI
import WidgetKit
import ModelSwitchboardCore

struct ModelSwitchboardStatusWidget: Widget {
    var kind: String {
        "ModelSwitchboardStatusWidget"
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SwitchboardWidgetConfigurationIntent.self, provider: SwitchboardTimelineProvider()) { entry in
            SwitchboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Model Switchboard")
        .description("Shows local model readiness and quick runtime context.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ModelSwitchboardWidgetBundle: WidgetBundle {
    var body: some Widget {
        ModelSwitchboardStatusWidget()
    }
}
