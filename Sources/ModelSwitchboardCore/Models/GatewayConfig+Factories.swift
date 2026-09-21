import Foundation

extension GatewayConfig {
    /// SSH-tunnel gateway. Illegal combination `.direct` + ssh fields is
    /// unrepresentable: an ssh gateway carries exactly the SSH payload.
    public static func ssh(
        id: String = UUID().uuidString,
        name: String,
        sshUser: String = "",
        sshHost: String = "",
        sshPort: Int = 22,
        remotePort: Int = 8877,
        identityFile: String? = nil,
        identityAgent: String? = nil,
        enabled: Bool = true
    ) -> GatewayConfig {
        GatewayConfig(
            id: id,
            name: name,
            enabled: enabled,
            connection: .ssh(.init(
                sshUser: sshUser,
                sshHost: sshHost,
                sshPort: sshPort,
                remotePort: remotePort,
                identityFile: identityFile,
                identityAgent: identityAgent
            ))
        )
    }

    /// Direct-URL gateway. Illegal combination `.ssh` + baseURL is
    /// unrepresentable: a direct gateway carries exactly the URL payload.
    public static func direct(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        remotePort: Int = 8877,
        deployHost: String? = nil,
        enabled: Bool = true
    ) -> GatewayConfig {
        GatewayConfig(
            id: id,
            name: name,
            enabled: enabled,
            connection: .direct(.init(baseURL: baseURL, remotePort: remotePort, deployHost: deployHost))
        )
    }
}
