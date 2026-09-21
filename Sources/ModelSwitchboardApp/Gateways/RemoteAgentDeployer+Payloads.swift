import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    func agentModulePayloads() throws -> [(String, String, Data)] {
        [
            ("push agent core", "agent_core.py", try Data(contentsOf: coreSourceURL)),
            ("push discovery", "discovery.py", try Data(contentsOf: discoverySourceURL)),
            ("push agent", "model_switchboard_agent.py", try Data(contentsOf: agentSourceURL)),
        ]
    }

    func remoteReplaceCommand(_ file: String) -> String {
        "mkdir -p ~/\(Self.remoteRoot) && cat > ~/\(Self.remoteRoot)/\(file).new && mv -f ~/\(Self.remoteRoot)/\(file).new ~/\(Self.remoteRoot)/\(file)"
    }

    func pairingLink(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).whitespaceTrimmed }
            .first { $0.hasPrefix("\(GatewayLinkCode.scheme)://") }
    }
}
