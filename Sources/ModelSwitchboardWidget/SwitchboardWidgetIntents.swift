import AppIntents
import WidgetKit
import ModelSwitchboardCore

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
