import SwiftUI
import ModelSwitchboardCore

extension GatewayConnectionField {
    static func ssh<Value>(
        _ editing: Binding<GatewayConfig>,
        _ keyPath: WritableKeyPath<GatewayConfig.Connection.SSH, Value>,
        fallback: Value
    ) -> Binding<Value> {
        bind(
            editing,
            extract: { if case .ssh(let ssh) = $0 { ssh } else { nil } },
            embed: { .ssh($0) },
            keyPath,
            fallback: fallback
        )
    }

    static func direct<Value>(
        _ editing: Binding<GatewayConfig>,
        _ keyPath: WritableKeyPath<GatewayConfig.Connection.Direct, Value>,
        fallback: Value
    ) -> Binding<Value> {
        bind(
            editing,
            extract: { if case .direct(let direct) = $0 { direct } else { nil } },
            embed: { .direct($0) },
            keyPath,
            fallback: fallback
        )
    }
}
