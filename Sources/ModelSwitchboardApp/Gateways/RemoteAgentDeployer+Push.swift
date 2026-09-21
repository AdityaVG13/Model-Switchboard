import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    func pushAgentModules(to ssh: GatewayConfig.Connection.SSH) async throws {
        // Push core + discovery + agent into the install root (installer
        // prefers pre-pushed modules over downloading anything). Core first:
        // discovery and the agent both import it.
        // SAFETY (cross-process file mutation): files land at
        // <file>.new first, then a single remote `mv -f` replaces the live
        // path atomically. Writing directly onto the live module could let
        // a concurrent `model-switchboard-agent` invocation exec a
        // partially-written Python file (SyntaxError mid-boot).
        for (step, file, data) in try agentModulePayloads() {
            _ = try await runSSH(
                ssh: ssh,
                step: step,
                remoteCommand: remoteReplaceCommand(file),
                stdin: data
            )
        }
    }
}
