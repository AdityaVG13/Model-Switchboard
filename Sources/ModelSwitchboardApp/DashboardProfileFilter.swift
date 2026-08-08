import Foundation
import ModelSwitchboardCore

/// Dashboard filter chip: fixed All/Running plus optional runtime family chips.
struct DashboardFilterChip: Hashable, Identifiable, Codable, Sendable {
    let id: String
    let label: String

    static let all = DashboardFilterChip(id: "all", label: "All")
    static let running = DashboardFilterChip(id: "running", label: "Running")

    static func runtime(_ label: String) -> DashboardFilterChip {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizeRuntimeLabel(trimmed)
        return DashboardFilterChip(id: "runtime:\(normalized)", label: trimmed)
    }

    var isRuntime: Bool { id.hasPrefix("runtime:") }

    var runtimeNeedle: String? {
        guard id.hasPrefix("runtime:") else { return nil }
        return String(id.dropFirst("runtime:".count))
    }

    static func normalizeRuntimeLabel(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

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
        func append(_ id: String) {
            guard !id.isEmpty, !seen.contains(id) else { return }
            seen.insert(id)
            out.append(id)
        }
        if ids.contains(DashboardFilterChip.all.id) {
            append(DashboardFilterChip.all.id)
        }
        if ids.contains(DashboardFilterChip.running.id) {
            append(DashboardFilterChip.running.id)
        }
        for id in ids where id != DashboardFilterChip.all.id && id != DashboardFilterChip.running.id {
            guard out.count < maxChips else { break }
            if id.hasPrefix("runtime:"), id.count > "runtime:".count {
                append(id)
            }
        }
        if out.isEmpty {
            return defaultChipIDs
        }
        if !out.contains(DashboardFilterChip.all.id) {
            out.insert(DashboardFilterChip.all.id, at: 0)
            if out.count > maxChips {
                out = Array(out.prefix(maxChips))
            }
        }
        return out
    }

    static func chips(fromIDs ids: [String]) -> [DashboardFilterChip] {
        ids.compactMap { id in
            if id == DashboardFilterChip.all.id { return .all }
            if id == DashboardFilterChip.running.id { return .running }
            if id.hasPrefix("runtime:") {
                let needle = String(id.dropFirst("runtime:".count))
                guard !needle.isEmpty else { return nil }
                let label = displayLabel(forRuntimeNeedle: needle)
                return DashboardFilterChip(id: id, label: label)
            }
            return nil
        }
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

    /// Candidate runtime chips from live profiles + builtins (Settings picker).
    static func availableRuntimeChips(fromStatuses statuses: [ModelProfileStatus]) -> [DashboardFilterChip] {
        var labels: [String] = builtinRuntimeLabels
        for status in statuses {
            let label = status.runtimeLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? status.runtime.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            // Prefer short family labels when tags exist.
            if let tags = status.runtimeTags {
                for tag in tags where !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labels.append(tag)
                }
            }
            labels.append(label)
        }
        var seen = Set<String>()
        var chips: [DashboardFilterChip] = []
        for label in labels {
            let chip = DashboardFilterChip.runtime(label)
            guard !seen.contains(chip.id) else { continue }
            seen.insert(chip.id)
            chips.append(chip)
        }
        return chips.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func matches(
        _ status: ModelProfileStatus,
        filterID: String,
        isDisplayedRunning: Bool,
        isBusy: Bool
    ) -> Bool {
        if filterID == DashboardFilterChip.all.id {
            return true
        }
        if filterID == DashboardFilterChip.running.id {
            return isDisplayedRunning || isBusy
        }
        guard filterID.hasPrefix("runtime:") else {
            // Unknown / stale selection must not silently match everything.
            return false
        }
        let needle = String(filterID.dropFirst("runtime:".count))
        guard !needle.isEmpty else { return false }
        return runtimeMatches(status, needle: needle)
    }

    static func runtimeHaystack(_ status: ModelProfileStatus) -> String {
        ([status.runtime, status.runtimeLabel ?? ""] + (status.runtimeTags ?? []))
            .joined(separator: " ")
            .lowercased()
    }

    /// Token-aware runtime match so short needles like "os" do not hit "ollama",
    /// while family chips like "mlx" still match "vllm mlx" / "vllm-mlx".
    static func runtimeMatches(_ status: ModelProfileStatus, needle: String) -> Bool {
        let haystack = runtimeHaystack(status)
        if haystack == needle { return true }
        if needle.contains(" "), haystack.contains(needle) { return true }

        var tokens: [String] = []
        for raw in haystack.split(whereSeparator: \.isWhitespace) {
            let token = String(raw)
            guard !token.isEmpty else { continue }
            tokens.append(token)
            if token.contains("-") {
                tokens.append(contentsOf: token.split(separator: "-").map(String.init))
            }
        }
        return tokens.contains(needle)
    }

    /// Legacy classification used by older tests / call sites.
    static func legacyRuntimeKind(_ status: ModelProfileStatus) -> String? {
        let haystack = runtimeHaystack(status)
        if haystack.contains("llama") { return "llama.cpp" }
        if haystack.contains("mlx") { return "mlx" }
        return nil
    }
}
