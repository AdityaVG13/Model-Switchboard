import Foundation

extension GatewayConfig.Connection {
    public struct SSH: Equatable, Sendable {
        public var sshUser: String
        public var sshHost: String
        public var sshPort: Int
        /// Port the agent listens on at the remote host's loopback.
        public var remotePort: Int
        /// Optional private key path passed to `ssh -i`.
        public var identityFile: String?
        /// Optional `IdentityAgent` socket (1Password, custom agents); GUI
        /// apps do not inherit a shell's SSH_AUTH_SOCK.
        public var identityAgent: String?

        public init(
            sshUser: String = "",
            sshHost: String,
            sshPort: Int = 22,
            remotePort: Int = 8877,
            identityFile: String? = nil,
            identityAgent: String? = nil
        ) {
            self.sshUser = sshUser
            self.sshHost = sshHost
            self.sshPort = sshPort
            self.remotePort = remotePort
            self.identityFile = identityFile
            self.identityAgent = identityAgent
        }

        /// `user@host`, or just `host` when the user is empty (OpenSSH default).
        public var destination: String {
            sshUser.isEmpty ? sshHost : "\(sshUser)@\(sshHost)"
        }

        /// OpenSSH treats argv tokens starting with `-` as options. Reject those
        /// for host/user so pasted pairing codes and settings cannot inject flags.
        public var hasUnsafeDestination: Bool {
            GatewayConfig.looksLikeSSHOption(sshHost)
                || (!sshUser.isEmpty && GatewayConfig.looksLikeSSHOption(sshUser))
        }
    }
}
