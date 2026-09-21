import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func upsertGateway(_ config: GatewayConfig, token: String) {
        let storage = tokenStorageFactory(config.id)
        // Empty field means "leave the keychain token alone" - never wipe a
        // saved token just because SecureField was blank on Save.
        if let trimmed = token.nonEmptyTrimmed {
            storage.save(trimmed)
        }
        var configs = GatewayConfigStore.load(from: defaults)
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        GatewayConfigStore.save(configs, to: defaults)
        applyConfigs(configs)
    }

    func removeGateway(id: String) {
        tokenStorageFactory(id).delete()
        let configs = GatewayConfigStore.load(from: defaults).filter { $0.id != id }
        GatewayConfigStore.save(configs, to: defaults)
        applyConfigs(configs)
    }
}
