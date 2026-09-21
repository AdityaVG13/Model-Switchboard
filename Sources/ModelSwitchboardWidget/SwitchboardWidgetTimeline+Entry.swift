import AppIntents
import OSLog
import WidgetKit
import ModelSwitchboardCore

extension SwitchboardTimelineProvider {
    func liveEntry(for configuration: SwitchboardWidgetConfigurationIntent) async throws -> SwitchboardWidgetEntry {
        let client = try ControllerClient(
            baseURLString: WidgetControllerConfig.defaultBaseURL,
            authToken: WidgetControllerConfig.authToken
        )
        let payload = try await client.fetchStatus()
        do {
            try ControllerStatusCache.write(payload)
        } catch {
            Self.logger.error("Cache write failed: \(String(describing: error), privacy: .public)")
        }
        return SwitchboardWidgetEntry(date: .now, configuration: configuration, payload: payload, errorDescription: nil)
    }

    func cachedOrFailedEntry(
        for configuration: SwitchboardWidgetConfigurationIntent,
        error: Error
    ) -> SwitchboardWidgetEntry {
        if let cached = ControllerStatusCache.load() {
            return SwitchboardWidgetEntry(
                date: cached.cachedAt,
                configuration: configuration,
                payload: cached.payload,
                errorDescription: "Controller unavailable. Showing cached state."
            )
        }
        return SwitchboardWidgetEntry(
            date: .now,
            configuration: configuration,
            payload: nil,
            errorDescription: UserFacingControllerError.description(for: error, isLocal: true)
                ?? "Controller unavailable."
        )
    }
}
