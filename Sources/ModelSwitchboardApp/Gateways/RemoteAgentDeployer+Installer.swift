import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    func installerInvocation(
        remotePort: Int,
        useTailscale: Bool,
        profilesDirectory: String?
    ) -> (prefix: String, flags: String) {
        var installerFlags = "--port \(remotePort)" + (useTailscale ? " --tailscale" : "")
        var remotePrefix = ""
        if let trimmed = profilesDirectory.nonEmptyTrimmed {
            // Prefer env so arbitrary paths (spaces, quotes) stay out of argv parsing.
            remotePrefix =
                "MODEL_SWITCHBOARD_PROFILES_DIR=\(Self.shellSingleQuoted(trimmed)) "
            if Self.isSimpleShellPath(trimmed) {
                installerFlags += " --profiles-dir \(trimmed)"
            }
        }
        return (remotePrefix, installerFlags)
    }
}
