import Foundation
import ModelSwitchboardCore

extension ControllerProfile {
    public var healthcheckMode: String {
        switch (values["HEALTHCHECK_MODE"] ?? "openai-models").lowercased() {
        case "http-200", "http200": return "http-200"
        case "disabled", "off", "none": return "disabled"
        default: return "openai-models"
        }
    }

    public var endpointHost: String {
        if let host = values["HOST"], !host.isEmpty {
            if host == "0.0.0.0" || host == "::" || host == "[::]" {
                return ControllerConfiguration.defaultHost
            }
            return host
        }
        return URL(string: baseURL)?.host ?? ControllerConfiguration.defaultHost
    }

    public var endpointPort: String {
        if let port = values["PORT"], !port.isEmpty { return port }
        return URL(string: baseURL)?.port.map(String.init) ?? ""
    }

    public var logPath: String {
        let raw = values["LOG_ALIAS"] ?? values["MODEL_ALIAS"] ?? name
        let safe = raw.map { $0.isLetter || $0.isNumber || "_.-".contains($0) ? $0 : "_" }
        return "/tmp/\(String(safe)).log"
    }

    public var endpointIdentity: String? {
        guard !endpointPort.isEmpty else { return nil }
        let host =
            ControllerConfiguration.isLoopback(endpointHost)
            ? "localhost"
            : endpointHost.strippingBrackets.lowercased()
        return "\(host):\(endpointPort)"
    }
}
