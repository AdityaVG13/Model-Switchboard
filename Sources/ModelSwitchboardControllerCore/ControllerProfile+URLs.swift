import Foundation
import ModelSwitchboardCore

extension ControllerProfile {
    public var baseURL: String {
        if let configured = values["BASE_URL"]?.nonEmptyTrimmed
        {
            return configured.hasSuffix("/") ? String(configured.dropLast()) : configured
        }
        guard let port = values["PORT"], !port.isEmpty else { return "" }
        let configuredHost =
            values["HOST"]?.trimmed
            ?? ControllerConfiguration.defaultHost
        let host =
            ControllerConfiguration.isLoopback(configuredHost)
            ? configuredHost : ControllerConfiguration.defaultHost
        let literal = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "http://\(literal):\(port)/v1"
    }

    public var healthcheckURL: String {
        if let configured = values["HEALTHCHECK_URL"], !configured.isEmpty { return configured }
        if healthcheckMode == "openai-models" {
            if let configured = values["MODEL_LIST_URL"], !configured.isEmpty { return configured }
            return baseURL.isEmpty ? "" : "\(baseURL)/models"
        }
        return baseURL
    }
}
