import Foundation
import ModelSwitchboardCore

enum DashboardFilterPreferences {
    static let maxChips = 6
    static let defaultChipIDs = ["all", "running", "runtime:mlx", "runtime:llama.cpp"]

    /// Builtin runtime chip candidates always offered in Settings.
    static let builtinRuntimeLabels = ["MLX", "llama.cpp", "vLLM", "Ollama"]

    static func decodeChipIDs(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              !decoded.isEmpty
        else {
            return defaultChipIDs
        }
        return sanitize(decoded)
    }

    static func encodeChipIDs(_ ids: [String]) -> String {
        let sanitized = sanitize(ids)
        guard let data = try? JSONEncoder().encode(sanitized),
              let text = String(data: data, encoding: .utf8)
        else {
            return "[\"all\",\"running\",\"runtime:mlx\",\"runtime:llama.cpp\"]"
        }
        return text
    }

    /// Keep All first, Running second when present, drop junk, cap at maxChips.
    static func sanitize(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        pinBuiltinChips(from: ids, seen: &seen, out: &out)
        appendRuntimeIDs(from: ids, seen: &seen, out: &out)
        return finalizedFilterIDs(out)
    }
}
