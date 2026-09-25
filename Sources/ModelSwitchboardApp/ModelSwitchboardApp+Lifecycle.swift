import SwiftUI
import AppKit
import ModelSwitchboardCore

extension ModelSwitchboardApp {
    static func loadAndMigrateAuthToken() -> String {
        let defaults = UserDefaults.standard
        let legacyKey = GatewayPlusMigration.legacyAuthTokenDefaultsKey
        let keychain = KeychainTokenStorage.shared.load() ?? ""
        if let oldToken = defaults.string(forKey: legacyKey), !oldToken.isEmpty {
            defaults.removeObject(forKey: legacyKey)
            if !keychain.isEmpty {
                return keychain
            }
            KeychainTokenStorage.shared.save(oldToken)
            return oldToken
        }
        return keychain
    }

    func applyControllerBindings() {
        if store.controllerBaseURL != controllerBaseURL {
            store.controllerBaseURL = controllerBaseURL
        }
        if store.controllerAuthToken != controllerAuthToken {
            store.controllerAuthToken = controllerAuthToken
        }
    }
}
