import Foundation
import ModelSwitchboardCore

/// Dashboard filter chip: fixed All/Running plus optional runtime family chips.
struct DashboardFilterChip: Hashable, Identifiable, Codable, Sendable {
    let id: String
    let label: String

    static let all = DashboardFilterChip(id: "all", label: "All")
    static let running = DashboardFilterChip(id: "running", label: "Running")

    static func runtime(_ label: String) -> DashboardFilterChip {
        let trimmed = label.trimmed
        let normalized = Self.normalizeRuntimeLabel(trimmed)
        return DashboardFilterChip(id: "runtime:\(normalized)", label: trimmed)
    }

    var isRuntime: Bool { id.hasPrefix("runtime:") }

    var runtimeNeedle: String? {
        guard id.hasPrefix("runtime:") else { return nil }
        return String(id.dropFirst("runtime:".count))
    }

    static func normalizeRuntimeLabel(_ raw: String) -> String {
        raw.trimmed.lowercased()
    }
}
