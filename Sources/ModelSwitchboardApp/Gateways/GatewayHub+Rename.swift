import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func authToken(forGateway id: String) -> String {
        tokenStorageFactory(id).load() ?? ""
    }

    /// Rename a gateway without restarting its tunnel or status store.
    @discardableResult
    func renameGateway(id: String, to name: String) -> Bool {
        guard let trimmed = name.nonEmptyTrimmed else { return false }
        var configs = GatewayConfigStore.load(from: defaults)
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return false }
        guard configs[index].name != trimmed else { return true }
        configs[index].name = trimmed
        GatewayConfigStore.save(configs, to: defaults)
        applyConfigs(configs)
        return true
    }
}
