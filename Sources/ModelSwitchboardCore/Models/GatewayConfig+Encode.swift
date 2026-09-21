import Foundation

extension GatewayConfig {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(kind, forKey: .kind)
        try encodeConnection(into: &container)
    }

    func encodeConnection(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch connection {
        case .direct(let details):
            try encodeDirect(details, into: &container)
        case .ssh(let details):
            try encodeSSH(details, into: &container)
        }
    }

    func encodeDirect(
        _ details: Connection.Direct,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(details.baseURL, forKey: .baseURL)
        try container.encode(details.remotePort, forKey: .remotePort)
        if let deployHost = Self.nonEmpty(details.deployHost) {
            try container.encode(deployHost, forKey: .deployHost)
        }
    }

    func encodeSSH(
        _ details: Connection.SSH,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(details.sshUser, forKey: .sshUser)
        try container.encode(details.sshHost, forKey: .sshHost)
        try container.encode(details.sshPort, forKey: .sshPort)
        try container.encode(details.remotePort, forKey: .remotePort)
        if let identityFile = Self.nonEmpty(details.identityFile) {
            try container.encode(identityFile, forKey: .identityFile)
        }
        if let identityAgent = Self.nonEmpty(details.identityAgent) {
            try container.encode(identityAgent, forKey: .identityAgent)
        }
    }
}
