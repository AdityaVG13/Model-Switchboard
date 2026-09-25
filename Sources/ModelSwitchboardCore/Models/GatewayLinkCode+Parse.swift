import Foundation

extension GatewayLinkCode {
    public static func parse(_ raw: String) -> GatewayConfig? {
        guard let components = urlComponents(from: raw) else { return nil }
        return gateway(from: components, raw: raw)
    }

    /// True when the authority carries an explicit but non-numeric port
    /// suffix (`host:ssh`, `host:`). Runs only after `urlComponents`
    /// validated the scheme/host, so unexpected shapes fail open to false
    /// (historic default-port behavior) rather than a new refusal.
    static func hasMalformedExplicitPort(raw: String) -> Bool {
        guard let schemeEnd = raw.range(of: "://") else { return false }
        let authority = raw[schemeEnd.upperBound...].prefix { !"/?#".contains($0) }
        let hostPort = authority.split(separator: "@").last ?? authority[...]
        let portText: Substring
        if hostPort.hasPrefix("[") {
            guard let close = hostPort.firstIndex(of: "]") else { return false }
            let rest = hostPort[hostPort.index(after: close)...]
            if rest.isEmpty { return false }
            guard rest.hasPrefix(":") else { return false }
            portText = rest.dropFirst()
        } else if let colon = hostPort.lastIndex(of: ":") {
            portText = hostPort[hostPort.index(after: colon)...]
        } else {
            return false
        }
        return portText.isEmpty || Int(portText) == nil
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

    static func gateway(from components: URLComponents, raw: String) -> GatewayConfig? {
        guard let host = components.host else { return nil }
        let query = components.queryItems ?? []
        let name = queryValue(query, "name").flatMap { $0.isEmpty ? nil : $0 } ?? host
        let agentPort: Int
        if let rawPort = queryValue(query, "agent_port") {
            // Present-but-malformed must refuse, not silently default: a
            // pasted link with `agent_port=abc` guessing 8877 would aim the
            // draft at the wrong agent without any signal.
            guard let parsed = Int(rawPort) else { return nil }
            agentPort = parsed
        } else {
            agentPort = 8877
        }
        guard isValidPort(agentPort) else { return nil }
        let sshPort: Int
        if let port = components.port {
            sshPort = port
        } else {
            // URLComponents reports both "no port" and "malformed port" as
            // nil; only the former may default to 22.
            guard !hasMalformedExplicitPort(raw: raw) else { return nil }
            sshPort = 22
        }
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
