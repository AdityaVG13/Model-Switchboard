import Foundation

extension GatewayLinkCode {
    public static func parse(_ raw: String) -> GatewayConfig? {
        guard let components = urlComponents(from: raw) else { return nil }
        return gateway(from: components)
    }

    static func urlComponents(from raw: String) -> URLComponents? {
        let trimmed = raw.trimmed
        guard
            let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == scheme,
            let host = components.host, !host.isEmpty,
            !GatewayConfig.looksLikeSSHOption(host)
        else { return nil }
        if let user = components.user, GatewayConfig.looksLikeSSHOption(user) {
            return nil
        }
        return components
    }

    static func gateway(from components: URLComponents) -> GatewayConfig? {
        guard let host = components.host else { return nil }
        let query = components.queryItems ?? []
        let name = queryValue(query, "name").flatMap { $0.isEmpty ? nil : $0 } ?? host
        let agentPort = queryValue(query, "agent_port").flatMap(Int.init) ?? 8877
        guard isValidPort(agentPort) else { return nil }
        let sshPort = components.port ?? 22
        guard isValidPort(sshPort) else { return nil }
        return gateway(
            mode: queryValue(query, "mode")?.lowercased(),
            name: name,
            host: host,
            user: components.user,
            sshPort: sshPort,
            agentPort: agentPort
        )
    }
}
