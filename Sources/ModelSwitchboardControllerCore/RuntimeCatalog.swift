import Foundation
import ModelSwitchboardCore

public struct RuntimeSpec: Sendable, Equatable {
    public let label: String
    public let tags: [String]
    public let launchMode: String
}

public enum RuntimeCatalog {
    public static func canonical(_ value: String?) -> String {
        let normalized = (value ?? "unknown").trimmed
            .lowercased().replacingOccurrences(of: "_", with: "-")
        return aliases[normalized] ?? normalized
    }

    public static func spec(for profile: ControllerProfile) -> RuntimeSpec {
        let spec =
            specs[profile.runtime]
            ?? RuntimeSpec(label: profile.runtime, tags: ["managed", "custom"], launchMode: "adapter")
        return RuntimeSpec(
            label: spec.label,
            tags: spec.tags,
            launchMode: launchMode(for: profile, fallback: spec.launchMode)
        )
    }
}
