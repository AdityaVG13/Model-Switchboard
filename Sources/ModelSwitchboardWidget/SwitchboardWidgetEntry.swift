import AppIntents
import WidgetKit
import ModelSwitchboardCore

enum WidgetControllerConfig {
    static let defaultBaseURL = ControllerEndpointDefaults.baseURLString
    static let reloadInterval: TimeInterval = 60

    static var authToken: String? {
        KeychainTokenStorage.shared.load()?.nonEmptyTrimmed
    }
}

struct SwitchboardWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: SwitchboardWidgetConfigurationIntent
    let payload: ControllerStatusPayload?
    let errorDescription: String?
}
