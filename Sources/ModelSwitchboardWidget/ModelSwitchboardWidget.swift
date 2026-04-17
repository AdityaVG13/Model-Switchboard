import AppIntents
import OSLog
import SwiftUI
import WidgetKit
import ModelSwitchboardCore

private enum WidgetControllerConfig {
    static let defaultBaseURL = "http://127.0.0.1:8877"
    static let reloadInterval: TimeInterval = 60
}

enum SwitchboardWidgetDisplayMode: String, AppEnum {
    case summary
    case readyFirst

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Display Mode")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .summary: .init(title: "Summary"),
        .readyFirst: .init(title: "Ready Models")
    ]
}

struct SwitchboardWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Switchboard Widget"
    static let description = IntentDescription("Choose what the widget emphasizes.")

    @Parameter(title: "Display Mode")
    var displayMode: SwitchboardWidgetDisplayMode?

    init() {
        displayMode = .summary
    }
}

struct RefreshSwitchboardWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Widget"
    static let description = IntentDescription("Reload the Model Switchboard widget timeline.")
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SwitchboardWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: SwitchboardWidgetConfigurationIntent
    let payload: ControllerStatusPayload?
    let errorDescription: String?
}

struct SwitchboardTimelineProvider: AppIntentTimelineProvider {
    private static let logger = Logger(subsystem: "io.modelswitchboard.widget", category: "timeline")

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

    private func makeEntry(for configuration: SwitchboardWidgetConfigurationIntent) async -> SwitchboardWidgetEntry {
        do {
            let client = try ControllerClient(baseURLString: WidgetControllerConfig.defaultBaseURL)
            let payload = try await client.fetchStatus()
            do {
                try ControllerStatusCache.write(payload)
            } catch {
                Self.logger.error("Cache write failed: \(String(describing: error), privacy: .public)")
            }
            return SwitchboardWidgetEntry(date: .now, configuration: configuration, payload: payload, errorDescription: nil)
        } catch {
            if let cached = ControllerStatusCache.load() {
                return SwitchboardWidgetEntry(
                    date: cached.cachedAt,
                    configuration: configuration,
                    payload: cached.payload,
                    errorDescription: "Controller unavailable. Showing cached state."
                )
            }
            return SwitchboardWidgetEntry(date: .now, configuration: configuration, payload: nil, errorDescription: error.localizedDescription)
        }
    }

    private var sampleStatuses: [ModelProfileStatus] {
        [
            ModelProfileStatus(
                profile: "qwen35-a3b",
                displayName: "Qwen3.5 35B A3B",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8080",
                baseURL: WidgetControllerConfig.defaultBaseURL,
                requestModel: "qwen35-local",
                serverModelID: "qwen35-local",
                pid: 12345,
                running: true,
                ready: true,
                serverIDs: ["qwen35-local"],
                rssMB: 21849.3,
                command: nil,
                logPath: "/tmp/qwen35-local.log"
            ),
            ModelProfileStatus(
                profile: "gemma4-e4b-obliterated",
                displayName: "Gemma 4 E4B",
                runtime: "llama.cpp",
                host: "127.0.0.1",
                port: "8082",
                baseURL: "http://127.0.0.1:8082/v1",
                requestModel: "gemma4-local",
                serverModelID: "gemma4-local",
                pid: nil,
                running: false,
                ready: false,
                serverIDs: [],
                rssMB: nil,
                command: nil,
                logPath: "/tmp/gemma.log"
            )
        ]
    }
}

struct ModelSwitchboardStatusWidget: Widget {
    private let features = AppFeatures.current
    var kind: String {
        switch features.edition {
        case .base:
            return "ModelSwitchboardStatusWidget"
        case .plus:
            return "ModelSwitchboardPlusStatusWidget"
        }
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SwitchboardWidgetConfigurationIntent.self, provider: SwitchboardTimelineProvider()) { entry in
            SwitchboardWidgetView(entry: entry)
        }
        .configurationDisplayName(features.appDisplayName)
        .description("Shows local model readiness and quick runtime context.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SwitchboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SwitchboardWidgetEntry
    private let features = AppFeatures.current

    private var statuses: [ModelProfileStatus] {
        (entry.payload?.statuses ?? []).sorted { lhs, rhs in
            if lhs.ready != rhs.ready { return lhs.ready && !rhs.ready }
            if lhs.running != rhs.running { return lhs.running && !rhs.running }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var summary: DashboardSummary {
        DashboardSummary(payload: entry.payload ?? ControllerStatusPayload(statuses: [], benchmark: nil, integrations: []))
    }

    private var displayMode: SwitchboardWidgetDisplayMode {
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
        .widgetURL(URL(string: features.edition == .plus ? "modelswitchboardplus://open" : "modelswitchboard://open"))
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(features.appDisplayName)
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold, design: .rounded))
                Text(modeTitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 8)
            Image(systemName: summary.menuBarSystemImage)
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold))
                .foregroundStyle(.mint)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .summary:
            summaryContent
        case .readyFirst:
            readyContent
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                metric(title: "Ready", value: "\(summary.readyProfiles)/\(summary.totalProfiles)")
                metric(title: "Running", value: "\(summary.runningProfiles)")
            }
            if let first = statuses.first {
                Text(first.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(first.stateDescription)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(statuses.prefix(family == .systemSmall ? 2 : 4)), id: \.profile) { profile in
                HStack(spacing: 8) {
                    Circle()
                        .fill(profile.ready ? Color.green : (profile.running ? Color.orange : Color.gray))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.displayName)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Text(profile.stateLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
            Spacer(minLength: 0)
            if family == .systemMedium {
                Button(intent: RefreshSwitchboardWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func offlineState(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Controller offline")
                .font(.caption.bold())
            Text(error)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(family == .systemSmall ? 3 : 4)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: family == .systemSmall ? 18 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeTitle: String {
        switch displayMode {
        case .summary:
            return "Summary"
        case .readyFirst:
            return "Ready models"
        }
    }
}

@main
struct ModelSwitchboardWidgetBundle: WidgetBundle {
    var body: some Widget {
        ModelSwitchboardStatusWidget()
    }
}
