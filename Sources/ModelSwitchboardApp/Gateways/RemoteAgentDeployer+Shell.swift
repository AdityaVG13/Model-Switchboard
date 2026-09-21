import Foundation
import ModelSwitchboardCore

extension RemoteAgentDeployer {
    /// Single-quote for remote `sh` so spaces/metacharacters in the path stay literal.
    nonisolated static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Paths safe to append as unquoted installer argv (no shell metacharacters).
    nonisolated static func isSimpleShellPath(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-~"))
        return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Machine-readable `AUTH_TOKEN=` line only (installer always emits it).
    nonisolated static func extractAuthToken(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map {
            String($0).whitespaceTrimmed
        }
        for line in lines {
            if line.hasPrefix("AUTH_TOKEN="), line.count > "AUTH_TOKEN=".count,
               let value = String(line.dropFirst("AUTH_TOKEN=".count)).nonEmptyTrimmed {
                return value
            }
        }
        return nil
    }
}
