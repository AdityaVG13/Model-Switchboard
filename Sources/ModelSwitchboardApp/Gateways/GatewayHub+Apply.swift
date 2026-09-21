import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func applyConfigs(_ configs: [GatewayConfig]) {
        var kept: [String: GatewayRuntime] = [:]
        for runtime in remoteRuntimes {
            guard let config = configs.first(where: { $0.id == runtime.id }) else {
                teardown(runtime)
                continue
            }
            switch Self.retention(of: runtime, matching: config) {
            case .keep:
                // Config Equatable ignores the Keychain token. Sync credentials
                // onto the kept store so token-only edits take effect without a
                // rebuild (and without waiting for app restart).
                syncAuthToken(onto: runtime)
                kept[runtime.id] = runtime
            case .rename:
                runtime.applyConfigPreservingConnection(config)
                syncAuthToken(onto: runtime)
                kept[runtime.id] = runtime
            case .replace:
                teardown(runtime)
            }
        }
        remoteRuntimes = configs.compactMap { config in
            if let existing = kept[config.id] { return existing }
            guard config.enabled else { return nil }
            return makeRuntime(config: config)
        }
    }
}
