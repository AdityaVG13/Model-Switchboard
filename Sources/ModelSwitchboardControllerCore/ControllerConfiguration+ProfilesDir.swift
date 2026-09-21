import Foundation
import ModelSwitchboardCore

extension ControllerConfiguration {
    /// Optional `config.json` next to the controller root: `{ "profiles_dir": "…" }`.
    public static func loadConfiguredProfilesDirectory(root: URL) -> URL? {
        let configURL = root.appendingPathComponent("config.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let path = (object["profiles_dir"] as? String)?.nonEmptyTrimmed
        else { return nil }
        return URL(fileURLWithPath: expandedPath(path), isDirectory: true)
    }

    public static func saveConfiguredProfilesDirectory(root: URL, profilesDirectory: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.json")
        var payload = try existingConfigObject(at: configURL) ?? [:]
        payload["profiles_dir"] = profilesDirectory.path
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    static func existingConfigObject(at configURL: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        let data = try Data(contentsOf: configURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ControllerError.operationFailed(
                "refusing to rewrite corrupt config.json: root value is not an object")
        }
        return object
    }
}
