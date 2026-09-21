import Foundation
import Security

extension KeychainTokenStorage {
    public func load() -> String? {
        // Prefer the non-group item first. Ad-hoc / local re-signs of the menu bar
        // app cannot always read App Group keychain items, and a failed group
        // probe used to surface as "token missing" so users re-pasted forever.
        if let value = load(accessGroup: nil), !value.isEmpty {
            return value
        }
        if let accessGroup, let value = load(accessGroup: accessGroup), !value.isEmpty {
            // Heal: mirror into the durable non-group slot so the next launch
            // (and ad-hoc rebuilds) keep working without a keychain prompt.
            _ = save(data: Data(value.utf8), accessGroup: nil)
            return value
        }
        return nil
    }

    public func save(_ token: String) {
        guard let trimmed = token.nonEmptyTrimmed else {
            delete()
            return
        }
        let data = Data(trimmed.utf8)
        // Always write the non-group item - this is what survives rebuilds of
        // ad-hoc signed debug installs without re-authorizing keychain access.
        _ = save(data: data, accessGroup: nil)
        // Best-effort App Group copy for the widget / shared suite.
        if let accessGroup {
            _ = save(data: data, accessGroup: accessGroup)
        }
    }

    public func delete() {
        if let accessGroup {
            _ = delete(accessGroup: accessGroup)
        }
        _ = delete(accessGroup: nil)
    }
}
