import Foundation

extension GatewayConfig {
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func recoveredDirectDeployHost(
        explicit: String?,
        leftoverUser: String?,
        leftoverHost: String?
    ) -> String? {
        if let explicit = nonEmpty(explicit) {
            return normalizedDeployHost(explicit)
        }
        guard let host = nonEmpty(leftoverHost), isIPv4Address(host) else {
            return nil
        }
        if let user = nonEmpty(leftoverUser) {
            return normalizedDeployHost("\(user)@\(host)")
        }
        return normalizedDeployHost(host)
    }
}
