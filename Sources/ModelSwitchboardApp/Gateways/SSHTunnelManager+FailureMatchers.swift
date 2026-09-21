import Foundation

extension SSHTunnelManager {
    static let failureMatchers: [FailureMatcher] = [
        FailureMatcher(
            needles: [
                "tailscale ssh requires",
                "to authenticate, visit https://login.tailscale.com",
            ],
            message: "Tailscale SSH needs re-auth for this host. Run `tailscale up` (or connect once) in Terminal, or set a Deploy host - an ssh-config alias - on the gateway in Settings.",
            requireAll: false
        ),
        FailureMatcher(
            needles: ["permission denied ("],
            message: "SSH auth failed. BatchMode needs a passphrase-less key or one loaded in an agent - run ssh-add, or set an identity file/agent for this gateway.",
            requireAll: false
        ),
        FailureMatcher(
            needles: ["permission denied", "publickey"],
            message: "SSH auth failed. BatchMode needs a passphrase-less key or one loaded in an agent - run ssh-add, or set an identity file/agent for this gateway.",
            requireAll: true
        ),
        FailureMatcher(
            needles: [
                "host key verification failed",
                "remote host identification has changed",
            ],
            message: "SSH host key problem. Connect once from Terminal to verify the host key, then reconnect.",
            requireAll: false
        ),
        FailureMatcher(
            needles: ["address already in use"],
            message: "Local forward port is in use. Remove the conflicting listener or re-add the gateway to pick a new port.",
            requireAll: false
        ),
        FailureMatcher(
            needles: ["connection refused"],
            message: "SSH connection refused. Check the host address and that sshd is running.",
            requireAll: false
        ),
        FailureMatcher(
            needles: ["timed out", "operation timed out"],
            message: "SSH connection timed out. Check that the host is reachable from this network.",
            requireAll: false
        ),
        FailureMatcher(
            needles: ["could not resolve hostname"],
            message: "Could not resolve the SSH host name.",
            requireAll: false
        ),
    ]
}
