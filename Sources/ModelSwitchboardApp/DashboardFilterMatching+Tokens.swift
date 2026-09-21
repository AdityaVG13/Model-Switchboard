import Foundation
import ModelSwitchboardCore

extension DashboardFilterPreferences {
    /// Token-aware runtime match so short needles like "os" do not hit "ollama",
    /// while family chips like "mlx" still match "vllm mlx" / "vllm-mlx".
    static func runtimeMatches(_ status: ModelProfileStatus, needle: String) -> Bool {
        let haystack = runtimeHaystack(status)
        if haystack == needle { return true }
        if needle.contains(" "), haystack.contains(needle) { return true }
        return expandedRuntimeTokens(haystack).contains(needle)
    }

    static func expandedRuntimeTokens(_ haystack: String) -> [String] {
        var tokens: [String] = []
        for raw in haystack.split(whereSeparator: \.isWhitespace) {
            let token = String(raw)
            guard !token.isEmpty else { continue }
            tokens.append(token)
            if token.contains("-") {
                tokens.append(contentsOf: token.split(separator: "-").map(String.init))
            }
        }
        return tokens
    }
}
