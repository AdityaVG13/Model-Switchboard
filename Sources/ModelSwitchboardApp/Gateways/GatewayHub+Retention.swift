import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    enum RuntimeRetention {
        case keep
        case rename
        case replace
    }

    static func retention(of runtime: GatewayRuntime, matching config: GatewayConfig) -> RuntimeRetention {
        if config == runtime.config { return .keep }
        if sameConnection(config, runtime.config) { return .rename }
        return .replace
    }
}
