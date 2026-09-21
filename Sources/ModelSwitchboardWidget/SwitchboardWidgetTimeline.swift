import AppIntents
import OSLog
import WidgetKit
import ModelSwitchboardCore

struct SwitchboardTimelineProvider: AppIntentTimelineProvider {
    static let logger = Logger(subsystem: "io.modelswitchboard.widget", category: "timeline")

    func placeholder(in context: Context) -> SwitchboardWidgetEntry {
        SwitchboardWidgetEntry(
            date: .now,
            configuration: SwitchboardWidgetConfigurationIntent(),
            payload: ControllerStatusPayload(statuses: sampleStatuses, benchmark: nil, integrations: []),
            errorDescription: nil
        )
    }

    func snapshot(for configuration: SwitchboardWidgetConfigurationIntent, in context: Context) async -> SwitchboardWidgetEntry {
        await makeEntry(for: configuration)
    }

    func timeline(for configuration: SwitchboardWidgetConfigurationIntent, in context: Context) async -> Timeline<SwitchboardWidgetEntry> {
        let entry = await makeEntry(for: configuration)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(WidgetControllerConfig.reloadInterval)))
    }

    func makeEntry(for configuration: SwitchboardWidgetConfigurationIntent) async -> SwitchboardWidgetEntry {
        do {
            return try await liveEntry(for: configuration)
        } catch {
            return cachedOrFailedEntry(for: configuration, error: error)
        }
    }
}
