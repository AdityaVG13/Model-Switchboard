import Foundation
import ModelSwitchboardCore

enum SSHInvocation {
    /// `prefix` + BatchMode + `extraOptions` + port/identity + `-- dest` [+ command].
    static func arguments(
        to target: Target,
        prefix: [String] = [],
        extraOptions: [String] = [],
        remoteCommand: String? = nil
    ) -> [String] {
        var arguments = prefix
        arguments += ["-o", "BatchMode=yes"]
        arguments += extraOptions
        if target.sshPort != 22 {
            arguments += ["-p", String(target.sshPort)]
        }
        if let identityFile = target.identityFile, !identityFile.isEmpty {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        if let identityAgent = target.identityAgent, !identityAgent.isEmpty {
            arguments += ["-o", "IdentityAgent=\(identityAgent)"]
        }
        arguments += ["--", target.destination]
        if let remoteCommand, !remoteCommand.isEmpty {
            arguments.append(remoteCommand)
        }
        return arguments
    }
}
