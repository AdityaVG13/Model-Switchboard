import Foundation
import ModelSwitchboardCore

extension DashboardFilterPreferences {
    static func chips(fromIDs ids: [String]) -> [DashboardFilterChip] {
        ids.compactMap(chip(fromID:))
    }

    static func chip(fromID id: String) -> DashboardFilterChip? {
        if id == DashboardFilterChip.all.id { return .all }
        if id == DashboardFilterChip.running.id { return .running }
        guard id.hasPrefix("runtime:") else { return nil }
        let needle = String(id.dropFirst("runtime:".count))
        guard !needle.isEmpty else { return nil }
        return DashboardFilterChip(id: id, label: displayLabel(forRuntimeNeedle: needle))
    }

    static func displayLabel(forRuntimeNeedle needle: String) -> String {
        for builtin in builtinRuntimeLabels {
            if DashboardFilterChip.normalizeRuntimeLabel(builtin) == needle {
                return builtin
            }
        }
        if needle == "llama.cpp" { return "llama.cpp" }
        if needle == "mlx" { return "MLX" }
        return needle
    }
}
