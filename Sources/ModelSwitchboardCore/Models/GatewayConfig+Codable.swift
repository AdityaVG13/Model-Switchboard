import Foundation

extension GatewayConfig {
    /// The persisted/encoded shape stays the old flat key set so existing
    /// UserDefaults blobs keep decoding. `kind` is the discriminator; only the
    /// active kind's keys are written, and foreign-kind keys in legacy blobs
    /// are ignored at decode (dropped on the next save).
    enum CodingKeys: String, CodingKey {
        case id, name, kind, enabled
        case baseURL, deployHost
        case sshUser, sshHost, sshPort, remotePort, identityFile, identityAgent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        switch try container.decode(GatewayKind.self, forKey: .kind) {
        case .direct:
            // Legacy blobs may carry dead ssh keys. A leftover IPv4 sshHost is
            // the working Tailscale/LAN deploy target after a kind switch
            // (MagicDNS URL + 100.x IP). Recover it as deployHost so Update
            // does not SSH to an unresolvable *.ts.net name.
            connection = .direct(.init(
                baseURL: try container.decode(String.self, forKey: .baseURL),
                remotePort: try container.decode(Int.self, forKey: .remotePort),
                deployHost: Self.recoveredDirectDeployHost(
                    explicit: try container.decodeIfPresent(String.self, forKey: .deployHost),
                    leftoverUser: try container.decodeIfPresent(String.self, forKey: .sshUser),
                    leftoverHost: try container.decodeIfPresent(String.self, forKey: .sshHost)
                )
            ))
        case .ssh:
            connection = .ssh(.init(
                sshUser: try container.decode(String.self, forKey: .sshUser),
                sshHost: try container.decode(String.self, forKey: .sshHost),
                sshPort: try container.decode(Int.self, forKey: .sshPort),
                remotePort: try container.decode(Int.self, forKey: .remotePort),
                identityFile: Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .identityFile)),
                identityAgent: Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .identityAgent))
            ))
        }
    }
}
