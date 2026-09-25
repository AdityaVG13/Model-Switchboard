import Foundation
import ModelSwitchboardCore

/// One-way first-launch import for Plus-edition users moving to the unified
/// app. Plus stored the same defaults keys under its own bundle domain; the
/// unified app (base bundle ID) reads them once via CFPreferences.
/// Gateways plus endpoint settings carry over; appearance prefs stay behind
/// (trivially re-set, not worth the coupling).
enum GatewayPlusMigration {
    static let legacyBundleID = "io.modelswitchboard.plus"
    /// Pre-keychain auth token defaults key, shared by both editions.
    static let legacyAuthTokenDefaultsKey = "controllerAuthToken"
    static let legacyEndpointKeys = [
        ControllerEndpointDefaults.baseURLUserDefaultsKey,
        legacyAuthTokenDefaultsKey,
    ]

    static func importIfNeeded(
        to defaults: UserDefaults,
        readLegacyValue: (String, String) -> Data? = { key, appID in
            CFPreferencesCopyAppValue(key as CFString, appID as CFString) as? Data
        },
        readLegacyString: (String, String) -> String? = { key, appID in
            CFPreferencesCopyAppValue(key as CFString, appID as CFString) as? String
        }
    ) {
        // Presence, not emptiness: an intentional empty list must never
        // re-import, a corrupt own blob must not be touched, and a
        // successful import writes the key so this runs exactly once.
        if defaults.data(forKey: GatewayConfigStore.defaultsKey) == nil,
            let data = readLegacyValue(GatewayConfigStore.defaultsKey, legacyBundleID),
            let gateways = try? JSONDecoder().decode([GatewayConfig].self, from: data),
            !gateways.isEmpty
        {
            GatewayConfigStore.save(gateways, to: defaults)
        }
        for key in legacyEndpointKeys {
            guard defaults.string(forKey: key) == nil,
                let value = readLegacyString(key, legacyBundleID),
                !value.isEmpty
            else { continue }
            defaults.set(value, forKey: key)
        }
    }
}
