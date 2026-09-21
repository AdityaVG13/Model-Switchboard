import Foundation
import ModelSwitchboardCore

extension DroidSyncService {
    func buildEntry(_ profile: ControllerProfile) throws -> [String: Any] {
        var entry: [String: Any] = [
            "displayName": profile.displayName,
            "model": profile.requestModel,
            "baseUrl": profile.baseURL,
            "apiKey": "not-needed",
            "provider": "generic-chat-completion-api",
            "maxOutputTokens": Int(profile["DROID_MAX_OUTPUT_TOKENS"] ?? "8192") ?? 8192,
            "noImageSupport": true,
        ]
        if let raw = profile["DROID_TEMPERATURE"], let temperature = Double(raw) {
            entry["extraArgs"] = ["temperature": temperature]
        }
        return entry
    }

    func droidID(_ profile: ControllerProfile) -> String {
        if let configured = profile["DROID_ID"], !configured.isEmpty { return configured }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_()$[] "))
        let cleaned = profile.displayName.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        }
        let slug = String(cleaned).split(whereSeparator: \.isWhitespace).joined(separator: "-")
        return "custom:\(slug)-0"
    }

    func replacements(_ profile: ControllerProfile) -> [String] {
        (profile["REPLACES_DISPLAY_NAMES"] ?? "").split(separator: ",")
            .compactMap { String($0).nonEmptyTrimmed }
    }
}
